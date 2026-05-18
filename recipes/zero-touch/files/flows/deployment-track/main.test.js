/**
 * flows/deployment-track/main.test.js
 *
 * Jest unit tests for the deployment-track flow.
 * Tests focus on the concurrency-safe in-flight tracking logic.
 */

import { describe, test, expect, beforeEach } from "@jest/globals";
import { onMessage } from "./main.js";

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const enc = new TextEncoder();

/**
 * Build a minimal flow message object.
 * @param {string} topic
 * @param {object|null} payloadObj - null/undefined emits an empty payload (cleared retain)
 */
function makeMsg(topic, payloadObj) {
    return {
        topic,
        payload: payloadObj != null ? enc.encode(JSON.stringify(payloadObj)) : new Uint8Array(0),
    };
}

/**
 * Create a fresh context with an empty mapper store.
 */
function makeCtx() {
    const store = new Map();
    return {
        mapper: {
            get(key) { return store.get(key) ?? null; },
            set(key, value) { store.set(key, value); },
        },
    };
}

/** Build a device_profile command message for the given cmdId and status. */
function cmdMsg(cmdId, status, extra = {}) {
    return makeMsg(`te/device/main///cmd/device_profile/${cmdId}`, {
        name: extra.name ?? "zone0@1.0.0",
        status,
        reason: status === "failed" ? (extra.reason ?? "Something went wrong") : undefined,
        ...extra,
    });
}

/** Extract the `state` value from the first output message, or null if no output. */
function lastState(outputs) {
    if (!outputs || outputs.length === 0) return null;
    const last = outputs[outputs.length - 1];
    return JSON.parse(last.payload).state;
}

/** Returns the topic of the first output message, or null. */
function firstTopic(outputs) {
    if (!outputs || outputs.length === 0) return null;
    return outputs[0].topic;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("deployment-track: single command", () => {
    let ctx;
    beforeEach(() => { ctx = makeCtx(); });

    test("executing → publishes in_progress", () => {
        const out = onMessage(cmdMsg("cmd-1", "executing"), ctx);
        expect(lastState(out)).toBe("in_progress");
    });

    test("executing then successful → publishes ok", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "successful"), ctx);
        expect(lastState(out)).toBe("ok");
    });

    test("executing then failed → publishes failed", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "failed"), ctx);
        expect(lastState(out)).toBe("failed");
    });

    test("failed reason is included in output", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "failed", { reason: "disk full" }), ctx);
        const parsed = JSON.parse(out[0].payload);
        expect(parsed.reason).toBe("disk full");
    });

    test("output topic uses sanitized group name", () => {
        const msg = cmdMsg("cmd-1", "executing", { name: "my/group@2.0" });
        const out = onMessage(msg, ctx);
        expect(firstTopic(out)).toBe("te/device/main///twin/c8y_continuous_deployment_state__my__group");
    });

    test("output message has retain=true and qos=1", () => {
        const out = onMessage(cmdMsg("cmd-1", "executing"), ctx);
        expect(out[0].mqtt).toEqual({ retain: true, qos: 1 });
    });

    test("empty payload (cleared retain) produces no output", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-1", null), ctx);
        expect(out).toHaveLength(0);
    });

    test("unknown name format (no @) produces no output", () => {
        const out = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-1", {
            name: "bad-name",
            status: "executing",
        }), ctx);
        expect(out).toHaveLength(0);
    });

    test("init status registers in-flight but does not publish state", () => {
        const out = onMessage(cmdMsg("cmd-1", "init"), ctx);
        expect(out).toHaveLength(0);
    });
});

describe("deployment-track: concurrent commands — key scenario", () => {
    let ctx;
    beforeEach(() => { ctx = makeCtx(); });

    /**
     * Reproduces the exact bug sequence from the README:
     *   1. cmd1 executing
     *   2. cmd2 executing
     *   3. cmd2 failed          ← must NOT publish 'failed' (cmd1 still running)
     *   4. cmd1 failed          ← must publish 'failed' (all settled)
     */
    test("cmd2 fails while cmd1 still executing: does NOT publish failed", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-2", "failed"), ctx);
        // must produce no output, or only in_progress — never 'failed'
        if (out.length > 0) {
            expect(lastState(out)).not.toBe("failed");
        }
    });

    test("after both cmds fail, publishes failed", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "failed"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "failed"), ctx);
        expect(lastState(out)).toBe("failed");
    });
});

describe("deployment-track: concurrent commands — further cases", () => {
    let ctx;
    beforeEach(() => { ctx = makeCtx(); });

    test("both cmds succeed: last successful publishes ok", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        onMessage(cmdMsg("cmd-1", "successful"), ctx);
        const out = onMessage(cmdMsg("cmd-2", "successful"), ctx);
        expect(lastState(out)).toBe("ok");
    });

    test("first successful does not emit ok while second is in flight", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "successful"), ctx);
        // must produce no output (cmd-2 still in flight)
        expect(out).toHaveLength(0);
    });

    test("empty payload cleanup removes from in-flight, last failure then publishes failed", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        // cmd-1 reaches terminal status first, removing it from the in-flight set
        onMessage(cmdMsg("cmd-1", "successful"), ctx);
        // deployment-apply then clears cmd-1's retained topic with an empty payload — no-op
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-1", null), ctx);
        // cmd-2 fails; cmd-1 is gone → set is now empty → should publish failed
        const out = onMessage(cmdMsg("cmd-2", "failed"), ctx);
        expect(lastState(out)).toBe("failed");
    });

    test("three concurrent: only last terminal publishes state", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        onMessage(cmdMsg("cmd-3", "executing"), ctx);
        expect(onMessage(cmdMsg("cmd-1", "failed"), ctx)).toHaveLength(0);
        expect(onMessage(cmdMsg("cmd-2", "successful"), ctx)).toHaveLength(0);
        const out = onMessage(cmdMsg("cmd-3", "successful"), ctx);
        expect(lastState(out)).toBe("ok");
    });

    test("multiple groups are tracked independently", () => {
        const ctxShared = makeCtx();
        // group A cmd-1 executing, group B cmd-2 executing
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-1", { name: "groupA@1.0", status: "executing" }), ctxShared);
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-2", { name: "groupB@1.0", status: "executing" }), ctxShared);
        // groupB cmd-2 fails → groupB should publish failed (its set is empty), groupA unaffected
        const outB = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-2", { name: "groupB@1.0", status: "failed" }), ctxShared);
        expect(lastState(outB)).toBe("failed");
        expect(firstTopic(outB)).toContain("groupB");
        // groupA cmd-1 succeeds independently
        const outA = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-1", { name: "groupA@1.0", status: "successful" }), ctxShared);
        expect(lastState(outA)).toBe("ok");
        expect(firstTopic(outA)).toContain("groupA");
    });
});

// ---------------------------------------------------------------------------
// Attempt counters
// ---------------------------------------------------------------------------

describe("deployment-track: attempt counters", () => {
    let ctx;
    beforeEach(() => { ctx = makeCtx(); });

    function parsedPayload(outputs) {
        return outputs.length > 0 ? JSON.parse(outputs[outputs.length - 1].payload) : null;
    }

    test("successful cmd: payload includes attempts=1, failedAttempts=0", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "successful"), ctx);
        const p = parsedPayload(out);
        expect(p.attempts).toBe(1);
        expect(p.failedAttempts).toBe(0);
    });

    test("failed cmd: payload includes attempts=1, failedAttempts=1", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-1", "failed"), ctx);
        const p = parsedPayload(out);
        expect(p.attempts).toBe(1);
        expect(p.failedAttempts).toBe(1);
    });

    test("two failures then success: attempts=3, failedAttempts=2 in ok payload", () => {
        // attempt 1: fail
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-1", "failed"), ctx);
        // attempt 2: fail
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "failed"), ctx);
        // attempt 3: success
        onMessage(cmdMsg("cmd-3", "executing"), ctx);
        const out = onMessage(cmdMsg("cmd-3", "successful"), ctx);
        const p = parsedPayload(out);
        expect(p.attempts).toBe(3);
        expect(p.failedAttempts).toBe(2);
    });

    test("concurrent: failed cmd increments counters even when state not published", () => {
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-2", "executing"), ctx);
        // cmd-1 fails; cmd-2 still in flight — state not published, but counters advance
        onMessage(cmdMsg("cmd-1", "failed"), ctx);
        // cmd-2 succeeds; now published with attempts=2, failedAttempts=1
        const out = onMessage(cmdMsg("cmd-2", "successful"), ctx);
        const p = parsedPayload(out);
        expect(p.state).toBe("ok");
        expect(p.attempts).toBe(2);
        expect(p.failedAttempts).toBe(1);
    });

    test("in_progress state includes attempt counters (reflecting history so far)", () => {
        const out = onMessage(cmdMsg("cmd-1", "executing"), ctx);
        const p = parsedPayload(out);
        expect(p.state).toBe("in_progress");
        expect(p.attempts).toBe(0);
        expect(p.failedAttempts).toBe(0);
    });

    test("in_progress after prior failures shows accumulated counts", () => {
        // first attempt fails
        onMessage(cmdMsg("cmd-1", "executing"), ctx);
        onMessage(cmdMsg("cmd-1", "failed"), ctx);
        // second attempt starts
        const out = onMessage(cmdMsg("cmd-2", "executing"), ctx);
        const p = parsedPayload(out);
        expect(p.state).toBe("in_progress");
        expect(p.attempts).toBe(1);
        expect(p.failedAttempts).toBe(1);
    });

    test("counters are independent per deployment group", () => {
        const ctxShared = makeCtx();
        // groupA: 1 failure
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-a1", { name: "groupA@1.0", status: "executing" }), ctxShared);
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-a1", { name: "groupA@1.0", status: "failed" }), ctxShared);
        // groupB: 1 success
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-b1", { name: "groupB@1.0", status: "executing" }), ctxShared);
        const outB = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-b1", { name: "groupB@1.0", status: "successful" }), ctxShared);
        const pB = parsedPayload(outB);
        expect(pB.attempts).toBe(1);
        expect(pB.failedAttempts).toBe(0);
        // groupA: now succeeds — should have attempts=2, failedAttempts=1 (not contaminated by groupB)
        onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-a2", { name: "groupA@1.0", status: "executing" }), ctxShared);
        const outA = onMessage(makeMsg("te/device/main///cmd/device_profile/cmd-a2", { name: "groupA@1.0", status: "successful" }), ctxShared);
        const pA = parsedPayload(outA);
        expect(pA.attempts).toBe(2);
        expect(pA.failedAttempts).toBe(1);
    });

    test("counters reset when deployment version changes", () => {
        // v1.0: two failures
        onMessage(cmdMsg("cmd-1", "executing", { name: "zone0@1.0" }), ctx);
        onMessage(cmdMsg("cmd-1", "failed",    { name: "zone0@1.0" }), ctx);
        onMessage(cmdMsg("cmd-2", "executing", { name: "zone0@1.0" }), ctx);
        onMessage(cmdMsg("cmd-2", "failed",    { name: "zone0@1.0" }), ctx);

        // v2.0: first attempt succeeds — counters should start from 0
        onMessage(cmdMsg("cmd-3", "executing", { name: "zone0@2.0" }), ctx);
        const out = onMessage(cmdMsg("cmd-3", "successful", { name: "zone0@2.0" }), ctx);
        const p = parsedPayload(out);
        expect(p.state).toBe("ok");
        expect(p.attempts).toBe(1);
        expect(p.failedAttempts).toBe(0);
    });
});
