// I18N dictionary using Unicode escape sequences (all ASCII-safe)
var I18N={
  ja:{welcome:'\u3088\u3046\u3053\u305d',wifi:'Wi-Fi',door_code:'\u30c9\u30a2\u30b3\u30fc\u30c9',check_in:'\u30c1\u30a7\u30c3\u30af\u30a4\u30f3',check_out:'\u30c1\u30a7\u30c3\u30af\u30a2\u30a6\u30c8',house_rules:'\u30cf\u30a6\u30b9\u30eb\u30fc\u30eb',emergency:'\u7d4a\u6025\u9023\u7d61\u5148',nearby:'\u5468\u8fba\u30b9\u30dd\u30c3\u30c8',copy:'\u30b3\u30d4\u30fc',copied:'\u30b3\u30d4\u30fc\u3057\u307e\u3057\u305f',scan_wifi:'\u30ab\u30e1\u30e9\u3067\u30b9\u30ad\u30e3\u30f3\u3057\u3066Wi-Fi\u306b\u63a5\u7d9a',add_home:'\u30db\u30fc\u30e0\u753b\u9762\u306b\u8ffd\u52a0',no_wifi:'Wi-Fi\u60c5\u5831\u306a\u3057',no_door:'\u30c9\u30a2\u30b3\u30fc\u30c9\u306a\u3057'},
  en:{welcome:'Welcome',wifi:'Wi-Fi',door_code:'Door Code',check_in:'Check-In',check_out:'Check-Out',house_rules:'House Rules',emergency:'Emergency',nearby:'Nearby',copy:'Copy',copied:'Copied!',scan_wifi:'Scan QR to connect Wi-Fi',add_home:'Add to Home Screen',no_wifi:'No Wi-Fi info',no_door:'No door code'},
  zh:{welcome:'\u6b22\u8fce',wifi:'Wi-Fi',door_code:'\u95e8\u7981\u5bc6\u7801',check_in:'\u5165\u4f4f',check_out:'\u9000\u623f',house_rules:'\u5165\u4f4f\u89c4\u5b9a',emergency:'\u7d27\u6025\u8054\u7cfb',nearby:'\u5468\u8fb9',copy:'\u590d\u5236',copied:'\u5df2\u590d\u5236',scan_wifi:'\u626b\u63cf\u4e8c\u7ef4\u7801\u8fde\u63a5Wi-Fi',add_home:'\u6dfb\u52a0\u5230\u4e3b\u5c4f\u5e55',no_wifi:'\u65e0Wi-Fi\u4fe1\u606f',no_door:'\u65e0\u95e8\u7981\u5bc6\u7801'},
  ko:{welcome:'\ud658\uc601\ud569\ub2c8\ub2e4',wifi:'Wi-Fi',door_code:'\ub3c4\uc5b4 \ucf54\ub4dc',check_in:'\uccb4\ud06c\uc778',check_out:'\uccb4\ud06c\uc544\uc6c3',house_rules:'\ud558\uc6b0\uc2a4 \uaddc\uce59',emergency:'\uae34\uae09 \uc5f0\ub77d\ucc98',nearby:'\uc8fc\ubcc0 \uba85\uc18c',copy:'\ubcf5\uc0ac',copied:'\ubcf5\uc0ac\ub428',scan_wifi:'QR\ub85c Wi-Fi \uc5f0\uacb0',add_home:'\ud648 \ud654\uba74\uc5d0 \ucd94\uac00',no_wifi:'Wi-Fi \uc815\ubcf4 \uc5c6\uc74c',no_door:'\ub3c4\uc5b4 \ucf54\ub4dc \uc5c6\uc74c'}
};
function t(k){return(I18N[CURRENT_LANG]||I18N.ja)[k]||k;}
function setLang(l){
  CURRENT_LANG=l;
  var labels={ja:'\u65e5\u672c\u8a9e',en:'English',zh:'\u4e2d\u6587',ko:'\ud55c\uad6d\uc5b4'};
  document.querySelectorAll('.lang-btn').forEach(function(b){
    b.classList.toggle('active',b.textContent.trim()===labels[l]);
  });
  document.querySelectorAll('[data-i18n]').forEach(function(el){el.textContent=t(el.dataset.i18n);});
}
function toggleSection(el){el.closest('.section').classList.toggle('open');}
function copyText(txt){
  if(navigator.clipboard){
    navigator.clipboard.writeText(txt).then(function(){showToast(t('copied'));}).catch(fb);
  } else fb();
  function fb(){
    var a=document.createElement('textarea');a.value=txt;
    a.style.cssText='position:fixed;opacity:0;top:0;left:0';
    document.body.appendChild(a);a.select();document.execCommand('copy');
    document.body.removeChild(a);showToast(t('copied'));
  }
}
function showToast(m){
  var el=document.getElementById('toast');
  el.textContent=m;el.classList.add('show');
  clearTimeout(el._t);el._t=setTimeout(function(){el.classList.remove('show');},2200);
}
function drawQR(){
  var canvas=document.getElementById('qr-canvas');
  if(!canvas||!WIFI_QR)return;
  try{
    var qr=new QRCode(0,'M');
    qr.addData(WIFI_QR);qr.make();
    var n=qr.getModuleCount(),cell=Math.floor(200/n),sz=n*cell;
    canvas.width=sz;canvas.height=sz;
    var ctx=canvas.getContext('2d');
    ctx.fillStyle='#fff';ctx.fillRect(0,0,sz,sz);
    ctx.fillStyle='#000';
    for(var r=0;r<n;r++)for(var c=0;c<n;c++)if(qr.isDark(r,c))ctx.fillRect(c*cell,r*cell,cell,cell);
  }catch(e){console.warn('QR',e);}
}
function renderNearby(){
  var wrap=document.getElementById('nearby-list');
  if(!wrap||!NEARBY||!NEARBY.length)return;
  NEARBY.forEach(function(p){
    var d=document.createElement('div');d.className='nearby-item';
    var icon=p.emoji||'\ud83d\udccd';
    var name=document.createElement('div');name.className='nearby-name';name.textContent=p.name||'';
    var sub=document.createElement('div');sub.className='nearby-sub';
    sub.textContent=(p.description||'')+(p.walk_minutes?' \xb7 '+p.walk_minutes+'min':'');
    var iconEl=document.createElement('span');iconEl.className='nearby-icon';iconEl.textContent=icon;
    var info=document.createElement('div');info.appendChild(name);info.appendChild(sub);
    d.appendChild(iconEl);d.appendChild(info);
    wrap.appendChild(d);
  });
}
function addToHome(){
  showToast('\u30d6\u30e9\u30a6\u30b6\u306e\u300c\u5171\u6709\u300d\u2192\u300c\u30db\u30fc\u30e0\u753b\u9762\u306b\u8ffd\u52a0\u300d\u3092\u9078\u629e');
}
window.addEventListener('DOMContentLoaded',function(){
  setLang(CURRENT_LANG);
  var first=document.querySelector('.section');if(first)first.classList.add('open');
  drawQR();
  renderNearby();
  if(MAPS_URL){var ml=document.querySelector('.map-btn');if(ml)ml.href=MAPS_URL;}
});
