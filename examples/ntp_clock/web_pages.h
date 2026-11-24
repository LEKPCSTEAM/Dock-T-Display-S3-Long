#pragma once

#include <pgmspace.h>

static const char PORTAL_HTML[] PROGMEM = R"rawliteral(<!DOCTYPE html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ตั้งค่า WiFi</title>
<style>
:root{--bg:#10141c;--card:#1a2130;--line:#2a3448;--fg:#e8edf6;--mut:#8b97ad;--acc:#4da3ff;--ok:#3ecf8e;--bad:#ff6b6b}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Noto Sans Thai",sans-serif;padding:16px;max-width:480px;margin:auto}
h1{font-size:22px;margin:8px 0 2px}
p.sub{color:var(--mut);margin:0 0 14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px;margin-bottom:14px}
.net{display:flex;align-items:center;gap:10px;width:100%;background:none;border:0;border-bottom:1px solid var(--line);color:var(--fg);font:inherit;padding:11px 4px;text-align:left;cursor:pointer}
.net:last-child{border-bottom:0}
.net:active{background:#222c40}
.net .n{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mut{color:var(--mut);font-size:14px}
label{display:block;margin:10px 0 4px;color:var(--mut);font-size:14px}
input[type=text],input[type=password]{width:100%;background:#0e121a;border:1px solid var(--line);border-radius:10px;color:var(--fg);font:inherit;padding:11px}
input:focus{outline:2px solid var(--acc);border-color:transparent}
.row{display:flex;align-items:center;gap:8px;margin-top:8px;color:var(--mut);font-size:14px}
button.p{width:100%;margin-top:14px;background:var(--acc);color:#05101e;border:0;border-radius:12px;font:inherit;font-weight:700;padding:13px;cursor:pointer}
button.s{background:none;border:1px solid var(--line);color:var(--fg);border-radius:10px;font:inherit;padding:8px 12px;cursor:pointer}
.hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}
.sp{width:42px;height:42px;border:4px solid var(--line);border-top-color:var(--acc);border-radius:50%;animation:r 1s linear infinite;margin:10px auto}
@keyframes r{to{transform:rotate(360deg)}}
.c{text-align:center}
.err{color:var(--bad)}.okc{color:var(--ok)}
.hide{display:none}
</style></head><body>
<h1>ตั้งค่า WiFi</h1>
<p class="sub">เลือกเครือข่ายให้นาฬิกาเชื่อมต่อ</p>
<div id="form">
<div class="card"><div class="hd"><b>เครือข่ายที่พบ</b><button class="s" id="rescan" type="button">สแกนใหม่</button></div>
<div id="list"></div><div class="mut c" id="scanmsg"></div></div>
<div class="card">
<label for="ssid">ชื่อ WiFi (SSID)</label>
<input type="text" id="ssid" maxlength="32" autocomplete="off" autocapitalize="off" spellcheck="false">
<div class="mut">เครือข่ายที่ซ่อนชื่อ ให้พิมพ์เอง</div>
<label for="pass">รหัสผ่าน</label>
<input type="password" id="pass" maxlength="63" autocomplete="off">
<div class="row"><input type="checkbox" id="show"><label for="show" style="margin:0">แสดงรหัสผ่าน</label></div>
<div class="err" id="ferr"></div>
<button class="p" id="go" type="button">เชื่อมต่อ</button>
</div></div>
<div id="prog" class="card c hide">
<div class="sp" id="spin"></div>
<div id="pmsg" style="font-size:18px;font-weight:700"></div>
<div id="pdet" class="mut"></div>
<button class="p hide" id="back" type="button">ลองใหม่</button>
</div>
<script>
(function(){
var $=function(i){return document.getElementById(i)};
var NS="http://www.w3.org/2000/svg";
function el(t,a){var e=document.createElementNS(NS,t);for(var k in a)e.setAttribute(k,a[k]);return e}
function bars(r){
var n=r>-55?4:r>-65?3:r>-75?2:1;
var s=el("svg",{width:22,height:18,viewBox:"0 0 22 18"});
for(var i=0;i<4;i++){var h=4+i*4;s.appendChild(el("rect",{x:i*6,y:18-h,width:4,height:h,rx:1,fill:i<n?"#4da3ff":"#3a455c"}))}
return s}
function lock(){
var s=el("svg",{width:14,height:16,viewBox:"0 0 14 16"});
s.appendChild(el("rect",{x:1,y:7,width:12,height:8,rx:2,fill:"#8b97ad"}));
s.appendChild(el("path",{d:"M4 7V5a3 3 0 0 1 6 0v2",fill:"none",stroke:"#8b97ad","stroke-width":2}));
return s}
var busy=false;
function render(d){
var l=$("list");l.textContent="";
$("scanmsg").textContent=d.list.length?"":(d.scanning?"กำลังค้นหา...":"ไม่พบเครือข่าย");
d.list.forEach(function(w){
var b=document.createElement("button");b.type="button";b.className="net";
b.appendChild(bars(w.rssi));
var n=document.createElement("span");n.className="n";n.textContent=w.ssid;b.appendChild(n);
if(w.secure)b.appendChild(lock());
b.onclick=function(){$("ssid").value=w.ssid;$("pass").focus()};
l.appendChild(b)})}
function scan(){
fetch("/scan").then(function(r){return r.json()}).then(render).catch(function(){})}
var tm=setInterval(function(){if(!busy)scan()},5000);
scan();
$("rescan").onclick=scan;
$("show").onchange=function(){$("pass").type=this.checked?"text":"password"};
function showProg(m,d,spin,back){
$("form").classList.add("hide");$("prog").classList.remove("hide");
$("pmsg").textContent=m;$("pdet").textContent=d||"";
$("spin").classList.toggle("hide",!spin);$("back").classList.toggle("hide",!back)}
function poll(){
fetch("/api/status").then(function(r){return r.json()}).then(function(s){
if(s.save==="ok"){showProg("เชื่อมต่อสำเร็จ","IP "+s.save_ip+" - นาฬิกาจะปิดโหมดตั้งค่าใน 8 วินาที เชื่อมต่อ WiFi เดิมของคุณอีกครั้ง",false,false);$("pmsg").className="okc";return}
if(s.save==="fail"){showProg("เชื่อมต่อไม่สำเร็จ","ตรวจสอบรหัสผ่านแล้วลองอีกครั้ง",false,true);$("pmsg").className="err";return}
setTimeout(poll,1000)}).catch(function(){setTimeout(poll,1500)})}
$("back").onclick=function(){busy=false;$("pmsg").className="";$("prog").classList.add("hide");$("form").classList.remove("hide");scan()};
$("go").onclick=function(){
var ssid=$("ssid").value;$("ferr").textContent="";
if(!ssid){$("ferr").textContent="กรุณาระบุชื่อ WiFi";return}
busy=true;showProg("กำลังเชื่อมต่อ...",ssid,true,false);$("pmsg").className="";
var b=new URLSearchParams();b.set("ssid",ssid);b.set("pass",$("pass").value);
fetch("/save",{method:"POST",body:b}).then(function(r){return r.json()}).then(function(j){
if(!j.ok){busy=false;$("prog").classList.add("hide");$("form").classList.remove("hide");$("ferr").textContent=j.err||"ผิดพลาด";return}
setTimeout(poll,1000)}).catch(function(){setTimeout(poll,1500)})};
})();
</script></body></html>)rawliteral";

static const char LAN_HTML[] PROGMEM = R"rawliteral(<!DOCTYPE html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LongDeck</title>
<style>
:root{--bg:#0f131a;--card:#182030;--line:#27324a;--fg:#e8edf6;--mut:#8b97ad;--acc:#4da3ff;--ok:#3ecf8e;--bad:#ff6b6b}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Noto Sans Thai",sans-serif;padding:16px;max-width:520px;margin:auto}
h1{font-size:22px;margin:6px 0 12px}
h2{font-size:16px;margin:0 0 10px;color:var(--mut);font-weight:600}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px;margin-bottom:14px}
#clk{font-size:44px;font-weight:700;text-align:center;font-variant-numeric:tabular-nums;letter-spacing:1px}
.kv{display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid var(--line)}
.kv span:first-child{color:var(--mut)}
.kv span:last-child{text-align:right;overflow-wrap:anywhere}
label.f{display:block;margin:12px 0 5px;color:var(--mut);font-size:14px}
input[type=text],input[type=number],select{width:100%;background:#0c1017;border:1px solid var(--line);border-radius:10px;color:var(--fg);font:inherit;padding:10px}
input[type=range]{width:100%;accent-color:var(--acc)}
.sw{display:flex;justify-content:space-between;align-items:center;padding:10px 0;border-top:1px solid var(--line)}
.sw input{width:46px;height:26px;accent-color:var(--acc)}
.g{display:grid;grid-template-columns:1fr 1fr;gap:8px}
button{width:100%;border-radius:12px;font:inherit;font-weight:600;padding:12px;cursor:pointer;border:1px solid var(--line);background:#1f2940;color:var(--fg);margin-top:10px}
button.p{background:var(--acc);color:#05101e;border:0}
button.d{color:var(--bad)}
button:active{opacity:.7}
#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:#2a3552;padding:10px 18px;border-radius:20px;opacity:0;transition:opacity .25s;pointer-events:none;max-width:90%}
#toast.on{opacity:1}
</style></head><body>
<h1>LongDeck</h1>
<div class="card"><div id="clk">--:--:--</div>
<div class="kv"><span>ซิงค์เวลาล่าสุด</span><span id="sync">-</span></div>
<div class="kv"><span>WiFi</span><span id="wifi">-</span></div>
<div class="kv"><span>IP</span><span id="ip">-</span></div>
<div class="kv"><span>สภาพอากาศ</span><span id="wx">-</span></div>
</div>
<form class="card" id="sf" onsubmit="return false">
<h2>ตั้งค่า</h2>
<label class="f" for="br">ความสว่าง <b id="brv"></b></label>
<input type="range" id="br" min="10" max="255">
<div class="sw"><span>โหมดกลางคืนอัตโนมัติ</span><input type="checkbox" id="an"></div>
<label class="f" for="th">ธีม</label>
<select id="th"><option value="0">สีประจำวัน</option><option value="1">สีรุ้ง</option><option value="2">ขาวเรียบ</option></select>
<label class="f" for="cp">เมือง (สำหรับสภาพอากาศ)</label>
<select id="cp"></select>
<label class="f" for="cn">ชื่อที่แสดง</label>
<input type="text" id="cn" maxlength="40">
<div class="g"><div><label class="f" for="la">ละติจูด</label><input type="number" id="la" step="0.0001" min="-90" max="90"></div>
<div><label class="f" for="lo">ลองจิจูด</label><input type="number" id="lo" step="0.0001" min="-180" max="180"></div></div>
<button class="p" id="save" type="button">บันทึกการตั้งค่า</button>
</form>
<div class="card">
<button id="bs" type="button">ซิงค์เวลาตอนนี้</button>
<button id="bw" type="button">เปลี่ยน WiFi</button>
<button id="br2" class="d" type="button">รีสตาร์ท</button>
</div>
<div id="toast"></div>
<script>
(function(){
var $=function(i){return document.getElementById(i)};
var CITIES=[["กรุงเทพฯ",13.7563,100.5018],["เชียงใหม่",18.7883,98.9853],["ขอนแก่น",16.4322,102.8236],["ภูเก็ต",7.8804,98.3923],["หาดใหญ่",7.0084,100.4747],["ชลบุรี",13.3611,100.9847],["นครราชสีมา",14.9799,102.0977],["อุดรธานี",17.4138,102.7870]];
var cp=$("cp");
CITIES.forEach(function(c,i){var o=document.createElement("option");o.value=i;o.textContent=c[0];cp.appendChild(o)});
var oc=document.createElement("option");oc.value="-1";oc.textContent="กำหนดเอง";cp.appendChild(oc);
cp.onchange=function(){var c=CITIES[+cp.value];if(c){$("cn").value=c[0];$("la").value=c[1];$("lo").value=c[2]}};
function matchCity(){
var la=parseFloat($("la").value),lo=parseFloat($("lo").value),idx=-1;
CITIES.forEach(function(c,i){if(Math.abs(c[1]-la)<0.0002&&Math.abs(c[2]-lo)<0.0002)idx=i});
cp.value=String(idx)}
$("la").oninput=$("lo").oninput=matchCity;
$("br").oninput=function(){$("brv").textContent=Math.round(this.value*100/255)+"%"};
var tt;
function toast(m){var t=$("toast");t.textContent=m;t.classList.add("on");clearTimeout(tt);tt=setTimeout(function(){t.classList.remove("on")},2600)}
function post(u,o){
var b=new URLSearchParams();for(var k in (o||{}))b.set(k,o[k]);
return fetch(u,{method:"POST",body:b}).then(function(r){return r.json()})}
fetch("/api/settings").then(function(r){return r.json()}).then(function(s){
$("br").value=s.brightness;$("br").oninput();
$("an").checked=s.auto_night;$("th").value=s.theme;
$("cn").value=s.city;$("la").value=s.lat;$("lo").value=s.lon;matchCity()}).catch(function(){toast("โหลดการตั้งค่าไม่สำเร็จ")});
$("save").onclick=function(){
post("/api/settings",{brightness:$("br").value,auto_night:$("an").checked?1:0,theme:$("th").value,city:$("cn").value,lat:$("la").value,lon:$("lo").value})
.then(function(j){toast(j.ok?"บันทึกแล้ว":"บันทึกไม่สำเร็จ")}).catch(function(){toast("เชื่อมต่อไม่ได้")})};
$("bs").onclick=function(){post("/api/sync").then(function(){toast("กำลังซิงค์เวลา...")}).catch(function(){toast("เชื่อมต่อไม่ได้")})};
$("bw").onclick=function(){
if(!confirm("เปิดโหมดตั้งค่า WiFi ใช่หรือไม่"))return;
post("/api/portal").then(function(j){toast("เชื่อมต่อ WiFi ชื่อ "+(j.ap||"LongDeck-xxxx")+" แล้วเปิด 192.168.4.1")}).catch(function(){toast("เชื่อมต่อไม่ได้")})};
$("br2").onclick=function(){
if(!confirm("รีสตาร์ทนาฬิกาใช่หรือไม่"))return;
post("/api/reboot").then(function(){toast("กำลังรีสตาร์ท...")}).catch(function(){toast("กำลังรีสตาร์ท...")})};
function p2(n){return n<10?"0"+n:""+n}
function wxText(c){
if(c===0)return"ท้องฟ้าโปร่ง";if(c<=3)return"มีเมฆ";if(c===45||c===48)return"หมอก";
if(c>=51&&c<=57)return"ฝนปรอย";if(c>=61&&c<=67)return"ฝนตก";if(c>=71&&c<=77)return"หิมะ";
if(c>=80&&c<=82)return"ฝนเป็นช่วง ๆ";if(c>=95)return"พายุฝนฟ้าคะนอง";return"-"}
var base=0,t0=0;
function tick(){
if(!base){$("clk").textContent="--:--:--";return}
var d=new Date((base+(Date.now()-t0)/1000+25200)*1000);
$("clk").textContent=p2(d.getUTCHours())+":"+p2(d.getUTCMinutes())+":"+p2(d.getUTCSeconds())}
setInterval(tick,1000);
function poll(){
fetch("/api/status").then(function(r){return r.json()}).then(function(s){
base=s.now;t0=Date.now();tick();
if(s.last_sync){var d=new Date((s.last_sync+25200)*1000);
$("sync").textContent=p2(d.getUTCDate())+"/"+p2(d.getUTCMonth()+1)+" "+p2(d.getUTCHours())+":"+p2(d.getUTCMinutes())}else $("sync").textContent="ยังไม่ซิงค์";
$("wifi").textContent=s.phase===2?(s.ssid+" ("+s.rssi+" dBm)"):"ไม่ได้เชื่อมต่อ";
$("ip").textContent=s.ip||"-";
var w=s.weather;
$("wx").textContent=w.valid?(s.city+" "+w.t.toFixed(1)+"°C ชื้น "+w.h+"% "+wxText(w.code)):"-"
}).catch(function(){});
}
poll();setInterval(poll,3000);
})();
</script></body></html>)rawliteral";
