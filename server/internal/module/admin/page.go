package admin

import (
	"github.com/gin-gonic/gin"
)

// page GET /admin —— 运营面板（v0.6.0 T10 tab 化）。
// 约束：HTML 在 Go raw string（反引号）内，JS 禁用模板字符串，沿用字符串拼接；
// 所有用户内容渲染前必须 esc() 转义（举报快照/巡检列表含任意用户输入）。
func (h *Handler) page(c *gin.Context) {
	c.Data(200, "text/html; charset=utf-8", []byte(adminPageHTML))
}

const adminPageHTML = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>拾光 · 运营面板</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:system-ui;background:#FAF8F3;color:#3A3A3A;max-width:880px;margin:24px auto;padding:0 16px}
h1{font-size:20px;margin-bottom:6px}
input,textarea,select,button{padding:8px 12px;border-radius:10px;border:1px solid #ECE6D8;font-size:14px;box-sizing:border-box}
button{background:#E89B3C;color:#fff;border:none;cursor:pointer;font-weight:600}
button.ghost{background:#fff;color:#C97F22;border:1px solid #ECE6D8;font-weight:400}
button.danger{background:#C25B4E}
table{width:100%;border-collapse:collapse;margin-top:12px;background:#fff;border-radius:12px;overflow:hidden}
td,th{padding:8px 10px;border-bottom:1px solid #ECE6D8;text-align:left;font-size:13px;vertical-align:top;word-break:break-all}
th{background:#F7E3C4;color:#C97F22;white-space:nowrap}
.tabs{display:flex;gap:6px;flex-wrap:wrap;margin-top:12px}
.tabs button{background:#fff;color:#6B6455;border:1px solid #ECE6D8;font-weight:400}
.tabs button.on{background:#E89B3C;color:#fff;border-color:#E89B3C;font-weight:600}
.tab{display:none;margin-top:8px}
.tab.on{display:block}
.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:10px}
#out{margin-top:10px;font-size:13px;color:#C25B4E;white-space:pre-wrap;min-height:16px}
.muted{color:#8A8578;font-size:12px}
.card{background:#fff;border:1px solid #ECE6D8;border-radius:12px;padding:10px 12px;margin-top:10px;font-size:13px}
.sn{white-space:pre-wrap;word-break:break-all;margin-top:4px;color:#555}
img.thumb{max-width:56px;max-height:56px;border-radius:8px;margin:3px 3px 0 0;vertical-align:top}
.bars{display:flex;align-items:flex-end;gap:4px;height:130px;margin-top:8px;background:#fff;border:1px solid #ECE6D8;border-radius:12px;padding:10px}
.bar{flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;gap:2px;min-width:0}
.bar i{display:block;background:#E89B3C;border-radius:3px 3px 0 0;width:100%}
.bar span{font-size:9px;color:#8A8578;white-space:nowrap}
</style></head><body>
<h1>拾光 · 运营面板</h1>
<div class="row"><input id="tk" placeholder="X-Admin-Token" size="30" type="password"> <button onclick="saveTk()">保存并刷新</button> <span class="muted">token 仅存本机 localStorage</span></div>
<div class="tabs" id="tabs"></div>
<div id="tab-stats" class="tab"></div>
<div id="tab-reports" class="tab"></div>
<div id="tab-users" class="tab"></div>
<div id="tab-content" class="tab"></div>
<div id="tab-announce" class="tab"></div>
<div id="tab-feedback" class="tab"></div>
<div id="tab-actions" class="tab"></div>
<div id="out"></div>
<script>
var TK=localStorage.getItem('admin_tk')||'';
document.getElementById('tk').value=TK;
function saveTk(){TK=document.getElementById('tk').value.trim();localStorage.setItem('admin_tk',TK);switchTab(cur)}
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function set(id,html){document.getElementById(id).innerHTML=html}
function showErr(e){document.getElementById('out').textContent=(e&&e.message)?e.message:''}
function fmtTime(s){return s?String(s).replace('T',' ').slice(0,16):''}
function imgs(j){try{var a=JSON.parse(j);if(!a||!a.length)return '';var h='';for(var i=0;i<a.length;i++)h+='<img class="thumb" src="'+esc(a[i])+'">';return h}catch(_){return ''}}
var PAGES={reports:1,users:1,checkins:1,comments:1,feedback:1,actions:1};
async function api(path,opts){var o=opts||{};o.headers=Object.assign({'X-Admin-Token':TK},o.headers||{});if(o.body&&!o.headers['Content-Type'])o.headers['Content-Type']='application/json';var r=await fetch(path,o);var j=await r.json();if(j.code!==0){throw new Error(j.message||('code '+j.code))}return j.data}

var TABS=[['stats','指标'],['reports','举报'],['users','用户'],['content','内容'],['announce','公告'],['feedback','反馈'],['actions','日志']];
var cur='stats';
function buildTabs(){var b='';for(var i=0;i<TABS.length;i++){b+='<button id="tb-'+TABS[i][0]+'">'+TABS[i][1]+'</button>'}set('tabs',b)}
document.getElementById('tabs').addEventListener('click',function(ev){var b=ev.target.closest('button');if(!b)return;switchTab(b.id.slice(3))});
function switchTab(t){cur=t;for(var i=0;i<TABS.length;i++){var on=TABS[i][0]===t;set('tab-'+TABS[i][0],'');document.getElementById('tab-'+TABS[i][0]).style.display=on?'block':'none';document.getElementById('tb-'+TABS[i][0]).className=on?'on':''}showErr({message:''});loadTab()}
function loadTab(){if(cur==='stats')loadStats();else if(cur==='reports'){PAGES.reports=1;loadReports()}else if(cur==='users'){PAGES.users=1;loadUsers()}else if(cur==='content')loadContent();else if(cur==='announce')renderAnnounce();else if(cur==='feedback'){PAGES.feedback=1;loadFeedback()}else if(cur==='actions'){PAGES.actions=1;loadActions()}}

// ---- 指标 ----
async function loadStats(){try{var d=await api('/admin/stats');var t=await api('/admin/stats/trend?days=14');
var h='<table><tr><th>指标</th><th>值</th></tr>';
h+='<tr><td>累计用户</td><td>'+d.users_total+'</td></tr>';
h+='<tr><td>近 7 天新增</td><td>'+d.users_new_7d+'</td></tr>';
h+='<tr><td>今日打卡</td><td>'+d.checkins_today+'</td></tr>';
h+='<tr><td>近 7 天打卡</td><td>'+d.checkins_7d+'</td></tr>';
h+='<tr><td>周活（WAU）</td><td>'+d.wau+'</td></tr>';
h+='<tr><td>北极星 · 周打卡≥3天占比</td><td>'+d.polar_star_pct.toFixed(1)+'%</td></tr></table>';
var max=1;for(var i=0;i<t.list.length;i++){if(t.list[i].checkins>max)max=t.list[i].checkins}
h+='<div class="muted" style="margin-top:12px">近 14 天打卡柱状（悬浮看 DAU/新增）</div><div class="bars">';
for(var i=0;i<t.list.length;i++){var p=t.list[i];var bh=Math.round(p.checkins/max*90);
h+='<div class="bar" title="'+p.date+' 打卡 '+p.checkins+' · DAU '+p.dau+' · 新增 '+p.new_users+'"><i style="height:'+(p.checkins>0?bh:1)+'px"></i><span>'+p.date.slice(5)+'</span></div>'}
h+='</div>';set('tab-stats',h)}catch(e){showErr(e)}}

// ---- 举报 ----
function ttName(t){return t===1?'打卡':(t===2?'留言':'用户')}
function stName(s){return s===0?'待处理':(s===1?'已处理':'驳回')}
async function loadReports(){try{var st=arguments.length>0?arguments[0]:'0';const d=await api('/admin/reports?status='+st+'&page='+PAGES.reports);
var h='<div class="row">状态 <select onchange="loadReports(this.value)">';
var opts=[['0','待处理'],['1','已处理'],['2','驳回'],['all','全部']];
for(var i=0;i<opts.length;i++){h+='<option value="'+opts[i][0]+'"'+(opts[i][0]===st?' selected':'')+'>'+opts[i][1]+'</option>'}
h+='</select> 共 '+d.total+' 条';
if(PAGES.reports>1)h+=' <button class="ghost" onclick="PAGES.reports--;loadReports(document.getElementById(\'rp-sel\')?document.getElementById(\'rp-sel\').value:\'0\')">上一页</button>';
if(PAGES.reports*d.page_size<d.total)h+=' <button class="ghost" onclick="PAGES.reports++;loadReports(document.getElementById(\'rp-sel\')?document.getElementById(\'rp-sel\').value:\'0\')">下一页</button>';
h+='</div>';
for(var i=0;i<d.list.length;i++){var r=d.list[i];var s=r.snapshot||{};
h+='<div class="card"><b>#'+r.id+'</b> · '+ttName(r.target_type)+' '+r.target_id+' · 举报理由 '+r.reason+' · '+(s.author?esc(s.author):'（已删）')+(s.author_id?'（uid '+s.author_id+'）':'')+' · '+fmtTime(r.created_at)+' · '+stName(r.status);
h+='<div class="sn">'+esc(s.content||'')+'</div>'+(s.images?imgs(s.images):'');
if(r.detail)h+='<div class="muted">举报说明：'+esc(r.detail)+'</div>';
if(r.status===0){h+='<div class="row"><button data-act="rp-del" data-id="'+r.id+'">删内容</button><button class="danger" data-act="rp-ban" data-id="'+r.id+'">封作者</button><button class="ghost" data-act="rp-dismiss" data-id="'+r.id+'">驳回</button></div>'}
h+='</div>'}
set('tab-reports',h)}catch(e){showErr(e)}}
async function handleReport(id,action){try{var note='';if(action!=='dismiss'){note=prompt(action==='ban_user'?'封禁原因（可空）：':'处理备注（可空）：')||''}await api('/admin/reports/'+id+'/handle',{method:'POST',body:JSON.stringify({action:action,note:note})});showErr({message:'已处理 #'+id});loadReports('0')}catch(e){showErr(e)}}

// ---- 用户 ----
async function loadUsers(){try{var kw=document.getElementById('u-kw')?document.getElementById('u-kw').value:'';const d=await api('/admin/users?keyword='+encodeURIComponent(kw)+'&page='+PAGES.users);
var h='<div class="row"><input id="u-kw" placeholder="昵称或用户 ID" value="'+esc(kw)+'" size="20"> <button onclick="PAGES.users=1;loadUsers()">搜索</button> 共 '+d.total+' 人';
if(PAGES.users>1)h+=' <button class="ghost" onclick="PAGES.users--;loadUsers()">上一页</button>';
if(PAGES.users*d.page_size<d.total)h+=' <button class="ghost" onclick="PAGES.users++;loadUsers()">下一页</button>';
h+='</div><table><tr><th>ID</th><th>昵称</th><th>打卡</th><th>状态</th><th>注册</th><th>操作</th></tr>';
for(var i=0;i<d.list.length;i++){var u=d.list[i];
h+='<tr><td>'+u.id+'</td><td>'+esc(u.nickname)+'</td><td>'+u.checkin_count+'</td><td>'+(u.status===1?'<span style="color:#C25B4E">封禁</span>':'正常')+'</td><td>'+fmtTime(u.created_at)+'</td><td><button class="ghost" data-act="u-detail" data-id="'+u.id+'">详情</button> '+(u.status===1?'<button class="ghost" data-act="u-unban" data-id="'+u.id+'">解封</button>':'<button class="danger" data-act="u-ban" data-id="'+u.id+'">封禁</button>')+'</td></tr>'}
h+='</table><div id="u-detail"></div>';set('tab-users',h)}catch(e){showErr(e)}}
async function userDetail(id){try{var d=await api('/admin/users/'+id);var u=d.user;
var h='<div class="card"><b>'+esc(u.nickname)+'</b>（uid '+u.id+'）· '+(u.status===1?'<span style="color:#C25B4E">封禁</span>':'正常')+' · 打卡 '+u.checkin_count+' 条 · 注册 '+fmtTime(u.created_at)+(u.bio?'<div class="muted">简介：'+esc(u.bio)+'</div>':'');
h+='<div class="muted" style="margin-top:6px">最近打卡（含未公开）</div>';
for(var i=0;i<d.recent_checkins.length;i++){var k=d.recent_checkins[i];
h+='<div class="sn">#'+k.id+' · '+k.checkin_date+' · 品类'+k.category+' · 可见'+k.visibility+(k.status===1?' · <span style="color:#C25B4E">已删</span>':'')+'<br>'+esc(k.content)+'</div>'+(k.images?imgs(k.images):'')}
h+='</div>';set('u-detail',h)}catch(e){showErr(e)}}
async function setUserStatus(id,st){try{if(st===1&&!confirm('确认封禁用户 '+id+'？其登录态将立即失效。'))return;await api('/admin/users/'+id+'/status',{method:'PUT',body:JSON.stringify({status:st})});showErr({message:'用户 '+id+' 已'+(st===1?'封禁':'解封')});loadUsers()}catch(e){showErr(e)}}

// ---- 内容 ----
async function loadContent(){try{var kw=document.getElementById('c-kw')?document.getElementById('c-kw').value:'';
var d=await api('/admin/checkins?keyword='+encodeURIComponent(kw)+'&page='+PAGES.checkins);
var h='<div class="row"><input id="c-kw" placeholder="搜索打卡正文" value="'+esc(kw)+'" size="20"> <button onclick="PAGES.checkins=1;loadContent()">搜打卡</button> 共 '+d.total+' 条';
if(PAGES.checkins>1)h+=' <button class="ghost" onclick="PAGES.checkins--;loadContent()">上一页</button>';
if(PAGES.checkins*d.page_size<d.total)h+=' <button class="ghost" onclick="PAGES.checkins++;loadContent()">下一页</button>';
h+='</div>';
for(var i=0;i<d.list.length;i++){var k=d.list[i];
h+='<div class="card">#'+k.id+' · '+esc(k.author||'uid '+k.user_id)+' · '+k.checkin_date+' · 品类'+k.category+' · 可见'+k.visibility+(k.status===1?' · <span style="color:#C25B4E">已删</span>':'')+'<div class="sn">'+esc(k.content)+'</div>'+(k.images?imgs(k.images):'');
if(k.status===0)h+='<div class="row"><button class="danger" data-act="c-del" data-id="'+k.id+'">下架</button></div>';
h+='</div>'}
var d2=await api('/admin/comments?keyword='+encodeURIComponent(kw)+'&page='+PAGES.comments);
h+='<div class="muted" style="margin-top:14px">留言（共 '+d2.total+' 条）</div>';
for(var i=0;i<d2.list.length;i++){var m=d2.list[i];
h+='<div class="card">#'+m.id+' · '+esc(m.author||'uid '+m.user_id)+' · 打卡'+m.checkin_id+' · '+fmtTime(m.created_at)+(m.status===1?' · <span style="color:#C25B4E">已删</span>':'')+'<div class="sn">'+esc(m.content)+'</div>';
if(m.status===0)h+='<div class="row"><button class="danger" data-act="m-del" data-id="'+m.id+'">删除</button></div>';
h+='</div>'}
set('tab-content',h)}catch(e){showErr(e)}}
async function delCheckin(id){try{if(!confirm('下架打卡 '+id+'？'))return;await api('/admin/checkins/'+id,{method:'DELETE'});showErr({message:'已下架 #'+id});loadContent()}catch(e){showErr(e)}}
async function delComment(id){try{if(!confirm('删除留言 '+id+'？'))return;await api('/admin/comments/'+id,{method:'DELETE'});showErr({message:'已删除 #'+id});loadContent()}catch(e){showErr(e)}}

// ---- 公告 ----
function renderAnnounce(){set('tab-announce','<div class="card"><div class="row"><textarea id="a-txt" rows="3" style="flex:1" maxlength="140" placeholder="公告内容（≤140 字，将出现在用户通知页）"></textarea></div><div class="row">定向用户 ID（逗号分隔，留空=全员正常用户）<input id="a-ids" size="24"> <button onclick="sendAnnounce(false)">发全员</button> <button class="ghost" onclick="sendAnnounce(true)">发定向</button></div></div>')}
async function sendAnnounce(targeted){try{var content=document.getElementById('a-txt').value.trim();if(!content){showErr({message:'公告内容不能为空'});return}var body={user_ids:null,content:content};
if(targeted){var raw=document.getElementById('a-ids').value.trim();if(!raw){showErr({message:'请填定向用户 ID'});return}var ids=[];var parts=raw.split(',');for(var i=0;i<parts.length;i++){var v=parseInt(parts[i].trim(),10);if(v>0)ids.push(v)}if(!ids.length){showErr({message:'定向 ID 无效'});return}body.user_ids=ids}
var d=await api('/admin/announcements',{method:'POST',body:JSON.stringify(body)});showErr({message:'已下发 '+d.sent+' 条'});}catch(e){showErr(e)}}

// ---- 反馈 ----
async function loadFeedback(){try{var st=arguments.length>0?arguments[0]:'0';const d=await api('/admin/feedback?status='+st+'&page='+PAGES.feedback);
var h='<div class="row">状态 <select onchange="loadFeedback(this.value)">';
var opts=[['0','待处理'],['1','已处理'],['all','全部']];
for(var i=0;i<opts.length;i++){h+='<option value="'+opts[i][0]+'"'+(opts[i][0]===st?' selected':'')+'>'+opts[i][1]+'</option>'}
h+='</select> 共 '+d.total+' 条</div>';
for(var i=0;i<d.list.length;i++){var f=d.list[i];
h+='<div class="card"><b>#'+f.id+'</b> · '+esc(f.author||'uid '+f.user_id)+' · '+fmtTime(f.created_at)+' · '+stName(f.status)+'<div class="sn">'+esc(f.content)+'</div>';
if(f.status===0)h+='<div class="row"><button class="ghost" data-act="fb-done" data-id="'+f.id+'">标记已处理</button></div>';
h+='</div>'}
set('tab-feedback',h)}catch(e){showErr(e)}}
async function markFeedback(id){try{await api('/admin/feedback/'+id+'/done',{method:'POST'});loadFeedback('0')}catch(e){showErr(e)}}

// ---- 日志 ----
async function loadActions(){try{const d=await api('/admin/actions?page='+PAGES.actions);
var h='<div class="row">共 '+d.total+' 条';
if(PAGES.actions>1)h+=' <button class="ghost" onclick="PAGES.actions--;loadActions()">上一页</button>';
if(PAGES.actions*d.page_size<d.total)h+=' <button class="ghost" onclick="PAGES.actions++;loadActions()">下一页</button>';
h+='</div><table><tr><th>时间</th><th>动作</th><th>目标</th><th>详情</th></tr>';
for(var i=0;i<d.list.length;i++){var a=d.list[i];
h+='<tr><td>'+fmtTime(a.created_at)+'</td><td>'+esc(a.action)+'</td><td>'+esc(a.target_type)+' #'+a.target_id+'</td><td>'+esc(a.detail)+'</td></tr>'}
h+='</table>';set('tab-actions',h)}catch(e){showErr(e)}}

// ---- 动作委托（避免 innerHTML 内联 onclick 的引号转义地狱） ----
document.body.addEventListener('click',function(ev){var el=ev.target.closest('[data-act]');if(!el)return;var id=el.dataset.id,act=el.dataset.act;
if(act==='rp-del')handleReport(+id,'delete_content');
else if(act==='rp-ban')handleReport(+id,'ban_user');
else if(act==='rp-dismiss')handleReport(+id,'dismiss');
else if(act==='u-detail')userDetail(+id);
else if(act==='u-ban')setUserStatus(+id,1);
else if(act==='u-unban')setUserStatus(+id,0);
else if(act==='c-del')delCheckin(+id);
else if(act==='m-del')delComment(+id);
else if(act==='fb-done')markFeedback(+id)});

buildTabs();
switchTab('stats');
</script></body></html>`
