import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ts from "typescript";
const compile = (source) =>
  ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
const original = readFileSync(
  new URL("../src/lib/referrals.ts", import.meta.url),
  "utf8",
);
const referral = await import(
  "data:text/javascript;base64," +
    Buffer.from(compile(original)).toString("base64")
);
const calls = [];
globalThis.__referralTransport = {
  get: async (url, options) => {
    calls.push({ url, options });
    return {
      data: {
        items: [
          {
            id: "relationship-id",
            missingConditions: ["KYC"],
            protectedOffer: true,
          },
        ],
        nextCursor: null,
      },
    };
  },
  request: async (request) => {
    calls.push(request);
    return { data: { status: "APPLIED", reason: null } };
  },
};
globalThis.__referralNormalize = referral.normalizeReferral;
const source = readFileSync(
  new URL("../src/lib/referralOperations.ts", import.meta.url),
  "utf8",
).replace(/^import .*;\n/gm, "");
const prefix =
  "const apiClient=globalThis.__referralTransport; const normalizeReferral=globalThis.__referralNormalize;\n";
const api = await import(
  "data:text/javascript;base64," +
    Buffer.from(compile(prefix + source)).toString("base64")
);
test("partial CSV execution includes only explicitly selected valid rows", () => {
  const rows = [
    { Row: 2, Status: "VALID" },
    { Row: 3, Status: "INVALID" },
    { Row: 4, Status: "APPLIED" },
    { Row: 5, Status: "VALID" },
  ];
  assert.deepEqual(api.selectedBulkRows(rows, [2, 3, 4, 2]), [2]);
  assert.deepEqual(api.selectedBulkRows(rows, []), []);
  assert.deepEqual(api.selectedBulkRows(rows, [5, 2]), [2, 5]);
});
test("relationship cursor/filter contract and response preserve source enums and false/null distinctions", async () => {
  const query = {
    programId: "program-id",
    search: "friend@example.com",
    source: "CAMPAIGN_LINK",
    stage: "KYC",
    afterId: 41,
    pageSize: 50,
  };
  const data = await api.relationshipApi.list(query);
  assert.equal(calls.at(-1).url, "/api/v1/admin/referrals/relationships");
  assert.deepEqual(calls.at(-1).options.params, query);
  assert.equal(data.Items[0].ProtectedOffer, true);
  assert.deepEqual(data.Items[0].MissingConditions, ["KYC"]);
  assert.equal(data.NextCursor, null);
});
test("support uses local customer mapping and encoded identity, never guesses an upstream user id", async () => {
  await api.relationshipApi.support("local/customer", {
    direction: "incoming",
    pageSize: 50,
  });
  assert.equal(
    calls.at(-1).url,
    "/api/v1/admin/customers/local%2Fcustomer/referrals",
  );
  assert.deepEqual(calls.at(-1).options.params, {
    direction: "incoming",
    pageSize: 50,
  });
});
test("invalid date cannot become an implicit now or malformed request", () => {
  for (const value of ["", "not-a-date"])
    assert.throws(() => api.utc(value), /valid date/);
  assert.equal(api.utc("2026-09-15T10:30:00Z"), "2026-09-15T10:30:00.000Z");
});
test("preview and execution commands retain reason/version/idempotency fields verbatim", async () => {
  const body = {
    Decision: "REJECT",
    Reason: "Verified duplicate source",
    ExpectedRevision: 4,
    IdempotencyKey: "stable-key",
  };
  const result = await api.referralSend(
    "POST",
    "/reviews/case-id/decisions",
    body,
  );
  assert.deepEqual(calls.at(-1), {
    method: "POST",
    url: "/api/v1/admin/referrals/reviews/case-id/decisions",
    data: body,
  });
  assert.equal(result.Status, "APPLIED");
  assert.equal(result.Reason, null);
});

test("contract normalization preserves locale keys and audit field paths exactly", () => {
  const source = {
    termsByLocale: { "en-US": "English terms", "pt-br": "Termos" },
    changes: { "policy.qualify_requires_kyc": { before: false, after: true } },
    beneficiaryBalances: { 123: "0.10" },
  };
  const normalized = api.normalizeOperation(source);
  assert.deepEqual(normalized.TermsByLocale, source.termsByLocale);
  assert.deepEqual(normalized.Changes, {
    "policy.qualify_requires_kyc": { Before: false, After: true },
  });
  assert.deepEqual(normalized.BeneficiaryBalances, { 123: "0.10" });
});
