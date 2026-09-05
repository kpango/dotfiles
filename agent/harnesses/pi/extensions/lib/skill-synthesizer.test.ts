import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  sanitizeSkillName,
  stripEphemeralPaths,
  validateSkillFrontmatter,
  formatSkillMarkdown,
  extractTrace,
  extractOperationalTrace,
  discoverExistingSkills,
  synthesizeSkillFromTrace,
  saveSkill,
  persistSkill,
  TaskExecutionTrace,
  SkillSpec,
} from "./skill-synthesizer-core";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

function eq<T>(name: string, actual: T, expected: T) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  check.name ? check(name, ok, `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`) : check(name, ok);
}

console.log("=== Skill Synthesizer Unit Tests ===");

// 1. sanitizeSkillName
eq("sanitize: normal kebab", sanitizeSkillName("my-cool-skill"), "my-cool-skill");
eq("sanitize: uppercase and spaces", sanitizeSkillName("My Cool Skill!"), "my-cool-skill");
eq("sanitize: underscores and dots", sanitizeSkillName("build_v2.0_test"), "build-v2-0-test");
eq("sanitize: multiple hyphens", sanitizeSkillName("---foo---bar---"), "foo-bar");
eq("sanitize: empty string fallback", sanitizeSkillName(""), "synthesized-skill");
eq("sanitize: non-string fallback", sanitizeSkillName(null as any), "synthesized-skill");

// 2. stripEphemeralPaths
eq(
  "stripEphemeralPaths: cleans /tmp paths",
  stripEphemeralPaths("Logged output to /tmp/run-12345/out.log"),
  "Logged output to <temp-path>/out.log"
);
eq(
  "stripEphemeralPaths: empty string",
  stripEphemeralPaths(""),
  ""
);

// 3. validateSkillFrontmatter
const validFm = validateSkillFrontmatter({
  name: "valid-skill-name",
  description: "A valid skill description for testing.",
});
check("validateSkillFrontmatter: valid case", validFm.valid && validFm.errors.length === 0);

const invalidNameFm = validateSkillFrontmatter({
  name: "Invalid Skill Name",
  description: "Some description",
});
check("validateSkillFrontmatter: invalid name rejected", !invalidNameFm.valid && invalidNameFm.errors.length > 0);

const emptyDescFm = validateSkillFrontmatter({
  name: "valid-name",
  description: "",
});
check("validateSkillFrontmatter: empty description rejected", !emptyDescFm.valid && emptyDescFm.errors.length > 0);

// 4. formatSkillMarkdown
const testSpec: SkillSpec = {
  frontmatter: {
    name: "test-distilled-skill",
    description: "Distilled procedure for testing skill synthesis.",
    "allowed-tools": ["bash", "read", "write"],
  },
  overview: "This is a distilled test skill overview.",
  trigger: "Run this when verifying synthesizer functionality.",
  procedure: [
    {
      step: 1,
      name: "Setup workspace",
      instruction: "Verify directories and create target files.",
      command: "mkdir -p /workspace/test",
    },
    {
      step: 2,
      name: "Run test suite",
      instruction: "Execute tests and confirm 0 exit code.",
      command: "bun test",
    },
  ],
  boundaryConditions: [
    "Do not execute outside test directory.",
    "Ensure tests exit 0 before continuing.",
  ],
  verificationMethod: "Run bun test to confirm all suites pass.",
};

const md = formatSkillMarkdown(testSpec);
check("formatSkillMarkdown: starts with frontmatter delimiter", md.startsWith("---\n"));
check("formatSkillMarkdown: contains name", md.includes("name: test-distilled-skill"));
check("formatSkillMarkdown: contains description", md.includes("description: Distilled procedure"));
check("formatSkillMarkdown: contains allowed-tools", md.includes("allowed-tools:\n  - bash"));
check("formatSkillMarkdown: contains title", md.includes("# Test Distilled Skill"));
check("formatSkillMarkdown: contains overview", md.includes("## Overview"));
check("formatSkillMarkdown: contains procedure", md.includes("### Step 1: Setup workspace"));
check("formatSkillMarkdown: contains bash block", md.includes("```bash\nbun test\n```"));
check("formatSkillMarkdown: contains boundary conditions", md.includes("## Boundary Conditions"));
check("formatSkillMarkdown: contains verification method", md.includes("## Verification Method"));

// 5. extractTrace
const sampleEvents = [
  { role: "user", content: "Implement and verify the new telemetry service" },
  {
    toolName: "bash",
    input: { command: "mkdir -p /tmp/telemetry-build && go test ./pkg/telemetry" },
    result: { stdout: "ok pkg/telemetry 0.42s\nSaved to /tmp/telemetry-build/report.txt", exitCode: 0 },
  },
  {
    toolName: "bash",
    input: { command: "git diff" },
    result: { stdout: "+ func TrackEvent() {}" },
  },
  {
    toolName: "read",
    input: { path: "pkg/telemetry/telemetry.go" },
    result: "package telemetry",
  },
];

const trace = extractTrace(sampleEvents);
eq("extractTrace: objective extracted", trace.objective, "Implement and verify the new telemetry service");
check("extractTrace: commands count", trace.commands.length === 2);
check("extractTrace: tools count", trace.tools.length === 3);
check("extractTrace: gitDiff extracted", trace.gitDiff === "+ func TrackEvent() {}");
check("extractTrace: verification evidence captured", Boolean(trace.verificationEvidence && trace.verificationEvidence.length === 1));
check("extractTrace: verification passed", trace.verificationEvidence?.[0]?.passed === true);
check(
  "extractTrace: ephemeral path stripped in stdout",
  trace.commands[0]?.stdout.includes("<temp-path>") === true
);


const traceAlias = extractOperationalTrace(sampleEvents);
eq("extractOperationalTrace: identical to extractTrace", traceAlias.commands.length, trace.commands.length);

// 6. discoverExistingSkills
const existingSkills = discoverExistingSkills();
check("discoverExistingSkills: has at least 34 skills", existingSkills.size >= 34);
check("discoverExistingSkills: contains benchmark", existingSkills.has("benchmark"));
check("discoverExistingSkills: contains swarm-evolve", existingSkills.has("swarm-evolve"));
check("discoverExistingSkills: contains golang-patterns", existingSkills.has("golang-patterns"));

// 7. synthesizeSkillFromTrace
const synthesized = synthesizeSkillFromTrace(trace);
check("synthesizeSkillFromTrace: name kebab sanitized", synthesized.frontmatter.name.length > 0);
check("synthesizeSkillFromTrace: has procedure steps", Boolean(synthesized.procedure && synthesized.procedure.length > 0));
check("synthesizeSkillFromTrace: has verification method", Boolean(synthesized.verificationMethod && synthesized.verificationMethod.length > 0));

// 8. saveSkill & persistSkill
const collisionSpec: SkillSpec = {
  frontmatter: {
    name: "benchmark",
    description: "Attempted collision on existing canonical skill.",
  },
  overview: "Collision test",
};
const collisionResult = saveSkill(collisionSpec, { overwrite: false });
check("saveSkill: collision detected and blocked", !collisionResult.persisted);
check("saveSkill: collision error message populated", collisionResult.error?.includes("already exists") === true);

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-skill-synth-test-"));
try {
  const newSpec: SkillSpec = {
    frontmatter: {
      name: "hermes-test-skill",
      description: "Test skill saved to temporary directory.",
      "allowed-tools": ["bash"],
    },
    overview: "Overview of hermes test skill.",
    trigger: "When running synthesizer unit tests.",
    procedure: [
      { step: 1, name: "Step one", instruction: "Do step one", command: "echo step 1" },
    ],
    boundaryConditions: ["Boundary condition 1"],
    verificationMethod: "Verification method 1",
  };

  const saveRes = saveSkill(newSpec, { skillsDir: tempDir });
  check("saveSkill: successfully persisted to new directory", saveRes.persisted);
  check("saveSkill: file exists on disk", fs.existsSync(saveRes.canonicalPath));

  const readBack = fs.readFileSync(saveRes.canonicalPath, "utf-8");
  check("saveSkill: read back content matches", readBack.includes("name: hermes-test-skill"));

  newSpec.overview = "Updated overview via persistSkill";
  const persistRes = persistSkill(tempDir, newSpec, true);
  check("persistSkill: overwrite allowed", persistRes.persisted);
  const readBack2 = fs.readFileSync(persistRes.canonicalPath, "utf-8");
  check("persistSkill: updated content reflected", readBack2.includes("Updated overview via persistSkill"));
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}


console.log(`\nskill-synthesizer.test: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
