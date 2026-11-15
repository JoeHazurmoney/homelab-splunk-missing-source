// Generates the Manage dashboard, splunk/apps/hl_data_health/default/data/ui/views/dh_manage.xml
// (task 12e). The view is written by this script: edit this file, not the XML, then run
//   node tools/gen_dh_manage.js            (rewrites the view)
//   node tools/gen_dh_manage.js <file>     (writes to <file> instead; tests/spl/run.sh compares)
// and deploy with tests/spl/dev-deploy.sh. docs/data-health/dashboards.md describes the result.
const fs = require("fs");
const path = require("path");
const out = process.argv[2] || path.join(__dirname, "..", "splunk", "apps", "hl_data_health", "default", "data", "ui", "views", "dh_manage.xml");

const GUIDE = (entry) => ` Guide (project repo): docs/data-health/dashboards.md > Manage > ${entry}`;
const ctx = (statics) => ({
  formattedConfig: { number: { prefix: '' } },
  formattedStatics: '>statics | formatByType(formattedConfig)',
  statics: statics || [],
  label: '>primary | seriesByName("label") | renameSeries("label") | formatByType(formattedConfig)',
  value: '>primary | seriesByName("value") | renameSeries("value") | formatByType(formattedConfig)',
});
const ITEMS = '>frame(label, value) | prepend(formattedStatics) | objects()';
const inputs = {};
const vis = (show, hide) => {
  const v = {};
  if (show) v.showConditions = show;
  if (hide) v.hideConditions = hide;
  return { visibility: v };
};
function text(id, title, token, opts = {}) {
  const o = { token };
  if (opts.def !== undefined) o.defaultValue = opts.def;
  if (opts.ph) o.placeholder = opts.ph;
  inputs[id] = { type: 'input.text', title, options: o };
}
function dd(id, title, token, items, def) {
  const o = { items, token };
  if (def !== undefined) o.defaultValue = def;
  inputs[id] = { type: 'input.dropdown', title, options: o };
}
function ddSearch(id, title, token, ds, opts = {}) {
  const o = { items: ITEMS, token };
  if (opts.def !== undefined) o.defaultValue = opts.def;
  if (opts.cascade) o.isCascadingInput = true;
  inputs[id] = { type: 'input.dropdown', title, options: o, dataSources: { primary: ds }, context: ctx(opts.statics) };
  if (opts.show) inputs[id].containerOptions = vis(opts.show);
}
const it = (label, value) => ({ label, value });

// ---------- inputs: Mute & thresholds
ddSearch('input_ov_host', 'Host', 'ov_host', 'ds_hosts', { def: '-' });
ddSearch('input_ov_entity', 'Item', 'ov_entity', 'ds_ov_entities', { def: '-', cascade: true });
dd('input_ov_action', 'Action', 'ov_action', [it('Mute', 'mute'), it('Unmute', 'unmute'), it('Set limit', 'threshold'), it('Clear limit', 'clear')], 'mute');
dd('input_ov_duration', 'Mute for', 'ov_duration', [it('1 hour', '3600'), it('4 hours', '14400'), it('1 day', '86400'), it('7 days', '604800'), it('30 days (the most allowed)', '2592000')], '3600');
text('input_ov_threshold', 'New limit in seconds (Set limit only)', 'ov_threshold', { def: '-' });
text('input_ov_reason', 'Reason (required)', 'ov_reason', { ph: 'Why? For example: patching, see CHG-123' });
text('input_ov_ticket', 'Ticket (optional, - for none)', 'ov_ticket', { def: '-' });
ddSearch('input_ov_confirm', 'Confirm (writes the change)', 'ov_confirm', 'ds_ov_confirm', { cascade: true, show: ['cond_ov_ready'] });
text('input_th_text', 'Search the thresholds (words separated by *)', 'th_text', { def: '*' });

// ---------- inputs: Expected list (add)
dd('input_ex_level', 'Level', 'ex_level', [it('Host (the host itself)', 'host'), it('Sourcetype (one kind of data)', 'sourcetype'), it('Source (one file or input)', 'source')], 'sourcetype');
ddSearch('input_ex_index', 'Index', 'ex_index', 'ds_indexes', { def: 'linux' });
text('input_ex_host', 'Host name', 'ex_host', { ph: 'For example pi5' });
text('input_ex_sourcetype', 'Sourcetype (not for a host row)', 'ex_sourcetype', { def: '-' });
text('input_ex_source', 'Source (source rows only)', 'ex_source', { def: '-' });
dd('input_ex_collection', 'Collection (how it arrives)', 'ex_collection', [it('uf (Splunk agent)', 'uf'), it('syslog', 'syslog'), it('hec (HTTP Event Collector)', 'hec')], 'uf');
text('input_ex_via', 'Via relay (optional, - for none)', 'ex_via', { def: '-' });
dd('input_ex_profile', 'Profile', 'ex_profile', [it('heartbeat (agent heartbeat, limit 90 s)', 'heartbeat'), it('periodic (runs every N seconds)', 'periodic'), it('continuous (steady stream, limit 15 min)', 'continuous'), it('sporadic (now and then, limit 24 h)', 'sporadic'), it('info (tracked, never alerts)', 'info')], 'continuous');
text('input_ex_interval', 'Interval in seconds (periodic only)', 'ex_interval', { def: '-' });
dd('input_ex_crit', 'Criticality', 'ex_crit', [it('1 (highest, alerts)', '1'), it('2 (alerts)', '2'), it('3 (no alert)', '3'), it('4 (lowest, no alert)', '4')], '2');
text('input_ex_owner', 'Owner (optional, - for none)', 'ex_owner', { def: '-' });
text('input_ex_site', 'Site (optional, - for none)', 'ex_site', { def: '-' });
text('input_ex_runbook', 'Runbook link (optional, - for none)', 'ex_runbook', { def: '-' });
text('input_ex_description', 'Description (optional, - for none)', 'ex_description', { def: '-' });
text('input_ex_reason', 'Reason (required)', 'ex_reason', { ph: 'Why? For example: new log file on pi5' });
text('input_ex_ticket', 'Ticket (optional, - for none)', 'ex_ticket', { def: '-' });
ddSearch('input_ex_confirm', 'Confirm (writes the change)', 'ex_confirm', 'ds_ex_confirm', { cascade: true, show: ['cond_ex_ready'] });

// ---------- inputs: Expected list (adopt)
ddSearch('input_ad_entity', 'Unregistered item', 'ad_entity', 'ds_ad_entities', { def: '-' });
dd('input_ad_crit', 'Criticality', 'ad_crit', [it('1 (highest, alerts)', '1'), it('2 (alerts)', '2'), it('3 (no alert)', '3'), it('4 (lowest, no alert)', '4')], '2');
text('input_ad_reason', 'Reason (required)', 'ad_reason', { ph: 'Why? For example: pi5 now sends cron logs' });
text('input_ad_ticket', 'Ticket (optional, - for none)', 'ad_ticket', { def: '-' });
ddSearch('input_ad_confirm', 'Confirm (writes the change)', 'ad_confirm', 'ds_ad_confirm', { cascade: true, show: ['cond_ad_ready'] });

// ---------- inputs: Test blocks
dd('input_bk_action', 'Action', 'bk_action', [it('Add a test block', 'add'), it('Remove a test block', 'remove')], 'add');
ddSearch('input_bk_host', 'Host', 'bk_host', 'ds_hosts', { def: '-' });
dd('input_bk_level', 'Block level', 'bk_level', [it('Whole host (all its data)', 'host'), it('One sourcetype', 'sourcetype'), it('One exact raw source', 'source')], 'host');
ddSearch('input_bk_target', 'Sourcetype or raw source', 'bk_target', 'ds_bk_targets', { def: '-', cascade: true });
dd('input_bk_duration', 'Block for', 'bk_duration', [it('5 minutes', '300'), it('15 minutes', '900'), it('1 hour', '3600'), it('4 hours', '14400'), it('24 hours (the most allowed)', '86400')], '900');
text('input_bk_reason', 'Reason (required: 3 to 120 letters, digits, spaces or _ . : / # ( ) -)', 'bk_reason', { ph: 'Why? For example: test that the app sees pi5 go missing' });

// ---------- inputs: Admin log
text('input_lg_text', 'Search the log (words separated by *)', 'lg_text', { def: '*' });

// ---------- conditions
const isSet = (toks) => toks.map((t) => `isSet($${t}$)`).join(' and ');
const R = {
  ov: ['ov_entity', 'ov_action', 'ov_duration', 'ov_threshold', 'ov_reason', 'ov_ticket'],
  ex: ['ex_level', 'ex_index', 'ex_host', 'ex_sourcetype', 'ex_source', 'ex_collection', 'ex_via', 'ex_profile', 'ex_interval', 'ex_crit', 'ex_owner', 'ex_site', 'ex_runbook', 'ex_description', 'ex_reason', 'ex_ticket'],
  ad: ['ad_entity', 'ad_crit', 'ad_reason', 'ad_ticket'],
  bk: ['bk_action', 'bk_host', 'bk_level', 'bk_target', 'bk_duration', 'bk_reason'],
};
const NAMES = { ov: 'Mute form', ex: 'Add-row form', ad: 'Adopt form', bk: 'Test-block form' };
const conditions = {};
for (const p of Object.keys(R)) {
  conditions[`cond_${p}_ready`] = { name: `${NAMES[p]} filled in`, value: isSet(R[p]) };
  // The test block is set by the Ansible role (task 11b): its form ends in a command, not a write
  if (p !== 'bk') conditions[`cond_${p}_done`] = { name: `${NAMES[p]} confirmed`, value: isSet([...R[p], `${p}_confirm`]) };
}

// ---------- data sources
const ds = {};
const S = (id, name, query) => { ds[id] = { type: 'ds.search', name, options: { query } }; };
const C = (id, name, extend, query) => { ds[id] = { type: 'ds.chain', name, options: { extend, query } }; };
const PREVIEW = '| table ui_change ui_item ui_now ui_after check | `dh_ui_headers`';
const CONFIRM = '| where dh_ok==1 | eval label=dh_label, value=dh_token | table label value';

S('ds_hosts', 'Hosts', '| `dh_ui_status(dh_status)` | stats count by host | eval label=host, value=host | table label value | appendpipe [| stats count | eval label="Choose a host", value="-" | table label value] | eval dh_o=if(value=="-", 0, 1) | sort 0 dh_o | table label value');
S('ds_ov_entities', 'Items of the host', '| `dh_ui_status(dh_status)` | where host==$ov_host|s$ | eval dh_lv=case(level=="host", 0, level=="sourcetype", 1, true(), 2), label=`dh_ui_item_words(entity_id)`." (".status.")", value=entity_id | sort 0 dh_lv entity_id | table label value | appendpipe [| stats count | eval label=if($ov_host|s$=="-", "Choose a host first", "Choose an item"), value="-" | table label value] | eval dh_o=if(value=="-", 0, 1) | sort 0 dh_o | table label value');
const ovReq = '| makeresults | eval entity_id=$ov_entity|s$, dh_action=$ov_action|s$, dh_secs=if($ov_action|s$=="mute", $ov_duration|s$, $ov_threshold|s$), reason=$ov_reason|s$, ticket=$ov_ticket|s$ | `dh_ui_actor` | `dh_ui_override_plan(dh_overrides, dh_admin_log, now())`';
S('ds_ov_plan', 'Mute or limit: plan', ovReq);
C('ds_ov_preview', 'Mute or limit: preview', 'ds_ov_plan', PREVIEW);
C('ds_ov_confirm', 'Mute or limit: confirmation choice', 'ds_ov_plan', CONFIRM);
S('ds_ov_apply', 'Mute or limit: apply', ovReq + ' | eval dh_confirm=$ov_confirm|s$ | `dh_ui_override_write(dh_overrides, dh_admin_log, now())` | `dh_ui_headers`');
S('ds_overrides', 'Current mutes and limit overrides', '| `dh_ui_overrides(dh_overrides)` | `dh_ui_headers`');
S('ds_thresholds', 'Thresholds', '| `dh_ui_status(dh_status)` | eval f_site="*", f_owner="*", f_index="*", f_crit="*", f_status="*", f_text=$th_text|s$ | `dh_ui_filter` | `dh_ui_thresholds(dh_baseline, dh_expected)` | `dh_ui_headers`');

S('ds_indexes', 'Indexes the app watches', '| `dh_ui_indexes` | appendpipe [| stats count | eval label="None (host row)", value="-" | table label value]');
const exReq = '| makeresults | eval dh_action="add", level=$ex_level|s$, index=$ex_index|s$, host=$ex_host|s$, sourcetype=$ex_sourcetype|s$, source=$ex_source|s$, collection=$ex_collection|s$, via=$ex_via|s$, profile=$ex_profile|s$, interval_secs=$ex_interval|s$, criticality=$ex_crit|s$, owner=$ex_owner|s$, site=$ex_site|s$, runbook=$ex_runbook|s$, description=$ex_description|s$, reason=$ex_reason|s$, ticket=$ex_ticket|s$ | `dh_ui_actor` | `dh_ui_expected_plan(dh_expected, dh_admin_log, now())`';
S('ds_ex_plan', 'Add an expected row: plan', exReq);
C('ds_ex_preview', 'Add an expected row: preview', 'ds_ex_plan', PREVIEW);
C('ds_ex_confirm', 'Add an expected row: confirmation choice', 'ds_ex_plan', CONFIRM);
S('ds_ex_apply', 'Add an expected row: apply', exReq + ' | eval dh_confirm=$ex_confirm|s$ | `dh_ui_expected_write(dh_expected, dh_admin_log, now())` | `dh_ui_headers`');
S('ds_unreg', 'Unregistered', '| `dh_ui_unregistered(dh_expected, dh_state_fast, dh_state_slow, dh_baseline, now())`');
C('ds_unreg_view', 'Unregistered (shown)', 'ds_unreg', '| eval ui_item=`dh_ui_item_words(entity_id)` | table ui_item level index host sourcetype sources last_seen first_seen suggested_profile days entity_id | `dh_ui_headers`');
C('ds_ad_entities', 'Unregistered choices', 'ds_unreg', '| eval label=`dh_ui_item_words(entity_id)`.", last seen ".last_seen, value=entity_id | table label value | appendpipe [| stats count | eval label="Choose an unregistered item", value="-" | table label value] | eval dh_o=if(value=="-", 0, 1) | sort 0 dh_o | table label value');
const adReq = '| makeresults | eval entity_id=$ad_entity|s$ | `dh_ui_adopt_row(dh_baseline, dh_fwd)` | eval criticality=$ad_crit|s$, reason=$ad_reason|s$, ticket=$ad_ticket|s$ | `dh_ui_actor` | `dh_ui_expected_plan(dh_expected, dh_admin_log, now())`';
S('ds_ad_plan', 'Adopt: plan', adReq);
C('ds_ad_preview', 'Adopt: preview', 'ds_ad_plan', PREVIEW);
C('ds_ad_confirm', 'Adopt: confirmation choice', 'ds_ad_plan', CONFIRM);
S('ds_ad_apply', 'Adopt: apply', adReq + ' | eval dh_confirm=$ad_confirm|s$ | `dh_ui_expected_write(dh_expected, dh_admin_log, now())` | `dh_ui_headers`');

S('ds_bk_sources', 'Raw sources of the host (24 h)', '| tstats count as events max(_indextime) as it where index IN (linux, windows, network) [| makeresults | eval host=$bk_host|s$ | `dh_ui_host_terms`] earliest=-24h latest=+1d by index sourcetype source | eval source_norm=`dh_source_norm(source)`, last_seen=strftime(it, `dh_ui_time_fmt_tz`) | sort 0 sourcetype source | table index sourcetype source source_norm events last_seen');
C('ds_bk_sources_view', 'Raw sources of the host (24 h) (shown)', 'ds_bk_sources', '| `dh_ui_headers`');
C('ds_bk_targets', 'Block target choices', 'ds_bk_sources', '| eval lvl=$bk_level|s$ | where lvl!="host" | eval value=if(lvl=="source", sourcetype."|".source, sourcetype."|*"), label=if(lvl=="source", sourcetype." › ".source." (exact raw name; normalized: ".source_norm.")", sourcetype) | stats count by label value | table label value | appendpipe [| stats count | eval label=case($bk_level|s$=="host", "Not needed for a whole-host block", $bk_level|s$=="source", "Choose the raw source", true(), "Choose the sourcetype"), value="-" | table label value] | eval dh_o=if(value=="-", 0, 1) | sort 0 dh_o | table label value');
const bkReq = '| makeresults | eval dh_action=$bk_action|s$, level=$bk_level|s$, host=$bk_host|s$, target=$bk_target|s$, dh_secs=$bk_duration|s$, reason=$bk_reason|s$ | `dh_ui_actor` | `dh_ui_block_plan(hl_ingest_block, now())`';
S('ds_bk_plan', 'Test block: plan', bkReq);
C('ds_bk_preview', 'Test block: preview', 'ds_bk_plan', '| table ui_change ui_item ui_now ui_after check source_norm | `dh_ui_headers`');
// The block lives in Cribl (spec 7.7, 7.8; task 11b): the form checks the request and shows the
// role's cribl_block command; it writes nothing itself.
C('ds_bk_command', 'Test block: command', 'ds_bk_plan', '| `dh_ui_block_command` | eval Command=coalesce(command, "Not ready: ".check) | table Command');
S('ds_blocks', 'Current test blocks', '| `dh_ui_blocks(hl_ingest_block, now())` | `dh_ui_headers`');

S('ds_log', 'Admin log', '| `dh_ui_admin_log(dh_admin_log)` | eval f_text=$lg_text|s$ | `dh_ui_hay_filter` | head 1000 | `dh_ui_headers`');

// ---------- visualizations
const viz = {};
const table = (id, title, dsId, desc, extra = {}) => {
  viz[id] = Object.assign({ type: 'splunk.table', title, dataSources: { primary: dsId }, options: { count: 25 }, description: desc + GUIDE(title) }, extra);
};
const md = (id, text, extra = {}) => { viz[id] = Object.assign({ type: 'splunk.markdown', options: { markdown: text } }, extra); };
const WAIT = '**Nothing written yet.** When the Check column of the preview says OK, open **Confirm** and choose the line that starts with **Apply**. That writes the change at once and records it on the Admin log tab.';

md('viz_mute_intro', '**Mute** an item during planned work, so it does not alert, or change how long it may stay silent before it counts as late (its **limit**). Fill in the form; the preview shows the change; nothing is written until you choose **Apply** under **Confirm**. Analysts may mute; every change is recorded on the Admin log tab. Times are in your Splunk time zone.');
md('viz_ov_steps', '**Preview: fill in the form above.** Choose the **Host**, then the **Item** (the host\'s own row, *whole host*, mutes everything it sends). Choose the **Action**, how long, and write a **Reason**. The preview of the change then appears here.', { containerOptions: vis(null, ['cond_ov_ready']) });
table('viz_ov_preview', 'Mute or limit: preview', 'ds_ov_preview', 'The change you are about to make, before and after, and whether it can be applied. Nothing is written yet.', { containerOptions: vis(['cond_ov_ready']) });
md('viz_ov_wait', WAIT, { containerOptions: vis(null, ['cond_ov_done']) });
table('viz_ov_result', 'Mute or limit: result', 'ds_ov_apply', 'What was written when you chose Apply.', { containerOptions: vis(['cond_ov_done']) });
table('viz_overrides', 'Current mutes and limit overrides', 'ds_overrides', 'Every mute and limit override in force.');
table('viz_thresholds', 'Thresholds: how long each item may stay silent', 'ds_thresholds', 'Each item\'s limit, where it comes from, and what the app has learned.');

md('viz_ex_intro', '**Add an expected row** (needs the dh_admin role): tell the app about data it should expect, so it alerts when that data stops. Rows that Ansible manages are changed in the Ansible inventory, not here. Nothing is written until you choose **Apply** under **Confirm**.');
md('viz_ex_steps', '**Preview: fill in the form above.** Choose the **Level**, enter the **Host name** (and the sourcetype or source for those levels), pick a **Profile**, and write a **Reason**. Optional boxes keep "-" for none. The preview of the change then appears here.', { containerOptions: vis(null, ['cond_ex_ready']) });
table('viz_ex_preview', 'Add an expected row: preview', 'ds_ex_preview', 'The expected-list row you are about to add or change, and whether it can be applied. Nothing is written yet.', { containerOptions: vis(['cond_ex_ready']) });
md('viz_ex_wait', WAIT, { containerOptions: vis(null, ['cond_ex_done']) });
table('viz_ex_result', 'Add an expected row: result', 'ds_ex_apply', 'What was written when you chose Apply.', { containerOptions: vis(['cond_ex_done']) });
table('viz_unreg', 'Unregistered: seen in the last 7 d but not expected', 'ds_unreg_view', 'Data that arrives but that nobody listed as expected. Adopt it below if it should be watched.');
md('viz_ad_intro', '**Adopt an unregistered item** (needs the dh_admin role): add a row of the table above to the expected list, with the collection and profile the app suggests. Nothing is written until you choose **Apply** under **Confirm**.');
md('viz_ad_steps', '**Preview: fill in the form above.** Choose the **Unregistered item**, its **Criticality**, and write a **Reason**. The preview of the change then appears here.', { containerOptions: vis(null, ['cond_ad_ready']) });
table('viz_ad_preview', 'Adopt: preview', 'ds_ad_preview', 'The expected row that adopting this item would add, and whether it can be applied. Nothing is written yet.', { containerOptions: vis(['cond_ad_ready']) });
md('viz_ad_wait', WAIT, { containerOptions: vis(null, ['cond_ad_done']) });
table('viz_ad_result', 'Adopt: result', 'ds_ad_apply', 'What was written when you chose Apply.', { containerOptions: vis(['cond_ad_done']) });

md('viz_bk_intro', 'A **test block** throws a host\'s real data away in Cribl Stream, before it reaches Splunk (linux, windows and network indexes only), so you can check that the app notices the data going missing. The Ansible role sets it: fill in the form, check the preview, then run the **command** it shows on pi5, in the repository\'s ansible folder. The block starts in Cribl about 20 seconds later and ends by itself; the table below lists it once the command has run. It needs the dh_admin role. Remove it as soon as the test is over: in production, a block is a way to blind monitoring.');
md('viz_bk_steps', '**Preview: fill in the form above.** Choose **Add** or **Remove**, the **Host** and the **Block level**; for one sourcetype or source, choose it in the next list (it fills from the host\'s data of the last 24 h, shown below). Write a **Reason**. The preview of the change then appears here.', { containerOptions: vis(null, ['cond_bk_ready']) });
table('viz_bk_preview', 'Test block: preview', 'ds_bk_preview', 'The block you are about to add or remove, and whether it can be applied. Nothing is written yet.', { containerOptions: vis(['cond_bk_ready']) });
table('viz_bk_command', 'Test block: command', 'ds_bk_command', 'The command that sets or removes this block, once the preview says OK. Run it on pi5; nothing is written from here.', { containerOptions: vis(['cond_bk_ready']) });
table('viz_bk_sources', 'Raw sources of the host (24 h)', 'ds_bk_sources_view', 'The exact source names the chosen host sent in the last 24 h; a source block must use one of them.');
table('viz_blocks', 'Current test blocks', 'ds_blocks', 'Data that is being thrown away on purpose for a test.');

table('viz_log', 'Admin log (every change made on Manage)', 'ds_log', 'Who changed what, when and why, newest first.');

// ---------- layouts
// Rows of [item, width] (an input is any id that starts with input_), placed left to right; each row
// has one height. Studio 10.6 renders a canvas input only when its box is at least 75 px tall after
// the grid padding (an 82 px row gives 74 px: "Too small to render content"), so input rows are 96.
const IH = 96;
function rows(spec) {
  const out = [];
  let y = 0;
  for (const [h, items] of spec) {
    let x = 0;
    for (const [item, w] of items) {
      const input = item.startsWith("input_");
      out.push({ item, type: input ? "input" : "block", position: { x, y, w, h } });
      x += w;
    }
    if (x !== 1440) throw new Error("row width " + x + " at y " + y);
    y += h;
  }
  return out;
}
const form = (p) => [
  [150, [[`viz_${p}_steps`, 480], [`viz_${p}_preview`, 960]]],
  [IH, [[`input_${p}_confirm`, 600], [`viz_${p}_wait`, 840]]],
  [150, [[`viz_${p}_result`, 1440]]],
];
const mute = rows([
  [70, [["viz_mute_intro", 1440]]],
  [IH, [["input_ov_host", 260], ["input_ov_entity", 460], ["input_ov_action", 220], ["input_ov_duration", 220], ["input_ov_threshold", 280]]],
  [IH, [["input_ov_reason", 960], ["input_ov_ticket", 480]]],
  ...form("ov"),
  [300, [["viz_overrides", 1440]]],
  [IH, [["input_th_text", 1440]]],
  [420, [["viz_thresholds", 1440]]],
]);
const expected = rows([
  [70, [["viz_ex_intro", 1440]]],
  [IH, [["input_ex_level", 260], ["input_ex_index", 260], ["input_ex_host", 300], ["input_ex_sourcetype", 300], ["input_ex_source", 320]]],
  [IH, [["input_ex_collection", 260], ["input_ex_via", 260], ["input_ex_profile", 300], ["input_ex_interval", 300], ["input_ex_crit", 320]]],
  [IH, [["input_ex_owner", 260], ["input_ex_site", 260], ["input_ex_runbook", 400], ["input_ex_description", 520]]],
  [IH, [["input_ex_reason", 960], ["input_ex_ticket", 480]]],
  ...form("ex"),
  [320, [["viz_unreg", 1440]]],
  [70, [["viz_ad_intro", 1440]]],
  [IH, [["input_ad_entity", 960], ["input_ad_crit", 480]]],
  [IH, [["input_ad_reason", 960], ["input_ad_ticket", 480]]],
  ...form("ad"),
]);
const blocks = rows([
  [90, [["viz_bk_intro", 1440]]],
  [IH, [["input_bk_action", 240], ["input_bk_host", 300], ["input_bk_level", 300], ["input_bk_target", 600]]],
  [IH, [["input_bk_duration", 240], ["input_bk_reason", 1200]]],
  [180, [["viz_bk_steps", 480], ["viz_bk_preview", 960]]],
  [180, [["viz_bk_command", 1440]]],
  [320, [["viz_bk_sources", 720], ["viz_blocks", 720]]],
]);
const log = rows([
  [IH, [["input_lg_text", 1440]]],
  [520, [["viz_log", 1440]]],
]);
const height = (s) => Math.max(...s.map((e) => e.position.y + e.position.h));
const L = (s) => ({ type: "grid", options: { width: 1440, height: height(s) }, structure: s });

const definition = {
  title: 'Manage',
  description: 'Mute data during planned work, change how long an item may stay silent, keep the expected list up to date and run test blocks; every change is previewed first and recorded in the admin log.',
  expressions: { conditions },
  inputs,
  defaults: { dataSources: { 'ds.search': { options: { queryParameters: { earliest: '-24h', latest: 'now' } } } } },
  dataSources: ds,
  visualizations: viz,
  layout: {
    tabs: { items: [
      { layoutId: 'layout_mute', label: 'Mute & thresholds' },
      { layoutId: 'layout_expected', label: 'Expected list' },
      { layoutId: 'layout_blocks', label: 'Test blocks (admin)' },
      { layoutId: 'layout_log', label: 'Admin log' },
    ] },
    layoutDefinitions: { layout_mute: L(mute), layout_expected: L(expected), layout_blocks: L(blocks), layout_log: L(log) },
    globalInputs: [],
    options: { submitOnDashboardLoad: false },
  },
};
const xml = `<dashboard version="2" theme="dark">
    <label>Manage</label>
    <description>${definition.description}</description>
    <definition><![CDATA[
${JSON.stringify(definition, null, 4)}
]]></definition>
    <meta type="hiddenElements"><![CDATA[
{
    "hideEdit": false,
    "hideOpenInSearch": false,
    "hideExport": false
}
]]></meta>
</dashboard>
`;
fs.writeFileSync(out, xml);
console.log('inputs', Object.keys(inputs).length, 'ds', Object.keys(ds).length, 'viz', Object.keys(viz).length);
