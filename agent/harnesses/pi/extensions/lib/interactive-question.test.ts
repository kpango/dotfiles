import { buildQuestionOptions, CUSTOM_INPUT_SENTINEL } from "../interactive-question";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}

// Normal: the custom sentinel is appended when allowed.
{
  const r = buildQuestionOptions(["A", "B"], true);
  check("append: 3 options with sentinel last", r.options.length === 3 && r.options[2] === CUSTOM_INPUT_SENTINEL);
  check("append: customAppended is true", r.customAppended === true);
}

// allowCustomInput false: no sentinel.
{
  const r = buildQuestionOptions(["A", "B"], false);
  check("no-custom: sentinel not appended", r.options.length === 2 && !r.options.includes(CUSTOM_INPUT_SENTINEL));
  check("no-custom: customAppended is false", r.customAppended === false);
}

// L4 regression: a user option equal to the sentinel is NOT duplicated and NOT
// treated as the custom trigger (customAppended=false), so selecting it returns
// it as a normal choice instead of being misrouted to the custom editor.
{
  const r = buildQuestionOptions([CUSTOM_INPUT_SENTINEL, "B"], true);
  check("collision: sentinel not duplicated", r.options.length === 2);
  check("collision: customAppended is false (no misroute)", r.customAppended === false);
  // Routing predicate the handler uses: `customAppended && choice === SENTINEL`.
  const routedToCustom = r.customAppended && CUSTOM_INPUT_SENTINEL === CUSTOM_INPUT_SENTINEL;
  check("collision: selecting the user's sentinel-named option is NOT routed to custom", routedToCustom === false);
}

// Empty / undefined options.
{
  check("empty: undefined options + custom -> [sentinel]", (() => {
    const r = buildQuestionOptions(undefined, true);
    return r.options.length === 1 && r.options[0] === CUSTOM_INPUT_SENTINEL && r.customAppended === true;
  })());
  check("empty: undefined options + no custom -> []", (() => {
    const r = buildQuestionOptions(undefined, false);
    return r.options.length === 0 && r.customAppended === false;
  })());
}

console.log(`\ninteractive-question: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
