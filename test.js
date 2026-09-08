const fs=require("fs"),vm=require("vm");
const ctx={};vm.createContext(ctx);
vm.runInContext(fs.readFileSync(require("path").join(__dirname,"SoundSource.js"),"utf8"),ctx);
const S=ctx;
let pass=0,fail=0;
const ok=(n,a,e)=>{const A=JSON.stringify(a),E=JSON.stringify(e);
  if(A===E){pass++;console.log("  ok   "+n)}else{fail++;console.log("  FAIL "+n+"\n        got "+A+"\n        want "+E)}};

// Real property sets captured from pw-dump on this machine.
const eq   ={"node.name":"output.omarchy.parametric-eq","media.name":"Omarchy Parametric EQ","media.role":"DSP","node.description":"Omarchy Parametric EQ"};
const qs   ={"node.name":"quickshell","media.name":"quickshell","media.role":"Notification"};
const rb   ={"node.name":"Rhythmbox","media.name":"Ö1 Service","application.name":"Rhythmbox","media.role":"Music"};
const play ={"node.name":"pw-play","media.role":"Music"};
const labels=S.mergedLabels({});

console.log("structural plumbing filter");
ok("EQ output is plumbing", S.isPlumbing({name:"output.omarchy.parametric-eq"},eq), true);
ok("Rhythmbox is not",      S.isPlumbing({name:"Rhythmbox"},rb), false);
ok("quickshell is not",     S.isPlumbing({name:"quickshell"},qs), false);
ok("ignore is not plumbing",S.isPlumbing({name:"Rhythmbox"},rb), false);

console.log("user ignore list");
ok("match by app name",     S.isIgnored({name:"Rhythmbox"},rb,["Rhythmbox"]), true);
ok("match is substring",    S.isIgnored({name:"Rhythmbox"},rb,["rhythm"]), true);
ok("match ignores case",    S.isIgnored({name:"Rhythmbox"},rb,["RHYTHMBOX"]), true);
ok("no match",              S.isIgnored({name:"Rhythmbox"},rb,["spotify"]), false);
ok("empty list",            S.isIgnored({name:"Rhythmbox"},rb,[]), false);
ok("blank entry ignored",   S.isIgnored({name:"Rhythmbox"},rb,["  "]), false);

console.log("ignore list editing");
ok("contains exact",        S.ignoreContains(["Slack","Discord"],"slack"), true);
ok("contains not partial",  S.ignoreContains(["Slack"],"sla"), false);
ok("contains empty label",  S.ignoreContains(["Slack"],""), false);
ok("add",                   S.withIgnored(["Slack"],"Discord",true), ["Slack","Discord"]);
ok("add is idempotent",     S.withIgnored(["Slack"],"Slack",true), ["Slack"]);
ok("remove",                S.withIgnored(["Slack","Discord"],"slack",false), ["Discord"]);
ok("remove absent is noop", S.withIgnored(["Slack"],"Firefox",false), ["Slack"]);
ok("add to empty",          S.withIgnored([],"Slack",true), ["Slack"]);
ok("undefined list",        S.withIgnored(undefined,"Slack",true), ["Slack"]);

console.log("labels");
ok("app name wins",   S.friendlyLabel(S.rawLabel({name:"Rhythmbox",description:""},rb),labels), "Rhythmbox");
ok("quickshell maps", S.friendlyLabel(S.rawLabel({name:"quickshell",description:""},qs),labels), "Omarchy shell");
ok("falls to node",   S.friendlyLabel(S.rawLabel({name:"pw-play",description:""},play),labels), "pw-play");
ok("user override",   S.friendlyLabel("pw-play",S.mergedLabels({"pw-play":"Test tone"})), "Test tone");

console.log("glyph + message");
ok("music -> note",    S.glyphFor(rb), S.GLYPH_NOTE);
ok("notify -> speaker",S.glyphFor(qs), S.GLYPH_SPEAKER);
ok("note is one char", S.GLYPH_NOTE.codePointAt(0), 0xf075a);
ok("speaker codepoint",S.GLYPH_SPEAKER.codePointAt(0), 0xf028);
ok("plain message",    S.messageFor("Slack",qs,false), "Slack");
ok("role appended",    S.messageFor("Slack",qs,true), "Slack  ·  Notification");

console.log("stream classification (no properties read)");
ok("stream+isSink",   S.isPlaybackStream({isStream:true,isSink:true}), true);
ok("capture stream",  S.isPlaybackStream({isStream:true,isSink:false,type:"Stream/Input/Audio"}), false);
ok("device not stream",S.isPlaybackStream({isStream:false,isSink:true}), false);

console.log("settings");
const d={duration:2000,repeatMs:1500,ignore:[]};
ok("defaults when absent", S.settingsFrom({plugins:[{id:"other"}]},"andi.sound-source",d), d);
ok("entry overrides", S.settingsFrom({plugins:[{id:"andi.sound-source",duration:5000}]},"andi.sound-source",d).duration, 5000);
ok("null ignored",    S.settingsFrom({plugins:[{id:"andi.sound-source",duration:null}]},"andi.sound-source",d).duration, 2000);
ok("no config",       S.settingsFrom(null,"andi.sound-source",d), d);

console.log("entry settings location");
const barCfg={bar:{layout:{left:[],center:[{id:"andi.sound-source",duration:9000}],right:[]}},plugins:[]};
const plugCfg={bar:{layout:{left:[],center:[],right:[]}},plugins:[{id:"andi.sound-source",duration:7000}]};
const bothCfg={bar:{layout:{left:[],center:[{id:"andi.sound-source",duration:9000}],right:[]}},
                plugins:[{id:"andi.sound-source",duration:7000}]};
ok("reads bar layout entry",  S.entrySettings(barCfg,"andi.sound-source"), {duration:9000});
ok("reads plugins entry",     S.entrySettings(plugCfg,"andi.sound-source"), {duration:7000});
ok("bar layout wins",         S.entrySettings(bothCfg,"andi.sound-source"), {duration:9000});
ok("absent -> empty",         S.entrySettings({plugins:[]},"andi.sound-source"), {});
ok("id stripped",             S.entrySettings(barCfg,"andi.sound-source").id, undefined);
ok("merged over defaults",    S.settingsFrom(barCfg,"andi.sound-source",{duration:2000,muted:false}),
                              {duration:9000,muted:false});
ok("position normalizes",     S.normalizePosition("bottom-center"), "bottom-center");
ok("bad position -> center",  S.normalizePosition("nowhere"), "center");

console.log("activeLabels");
const nodes=[
  {id:1,ready:true,name:"output.omarchy.parametric-eq",description:"",properties:eq},
  {id:2,ready:true,name:"Rhythmbox",description:"",properties:rb},
  {id:3,ready:true,name:"Rhythmbox",description:"",properties:rb},   // dedup
  {id:4,ready:false,name:"quickshell",description:"",properties:qs},  // unbound
];
ok("dedup, skip DSP + unbound", S.activeLabels(nodes,labels), ["Rhythmbox"]);

console.log("\n"+pass+" passed, "+fail+" failed");
process.exit(fail?1:0);
