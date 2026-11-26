const by=id=>document.getElementById(id), post=(name,data={})=>window.webkit.messageHandlers.host.postMessage({name,...data});
let cards=new Map(),stamp='',mapMessage='',selection=-1;
const is3d=()=>mode==='three'||mode==='design';
let viewer,glError='',mode='three',token='',active='',pathOK=false,busy=false,error='',original=[],palette=[],used=[],details='',plate='',sent='',photoScale=1,photoPan=[0,0];
try {viewer=new PathViewer(by('gl'));} catch(e){glError=e.message;}
let sources = [];
function setSources({list,id}){
  sources = list;
  const sel=by('sources');sel.replaceChildren();
  for(const item of list)sel.add(new Option(displayText(item.label),item.id));
  if(!list.length)sel.add(new Option(t('noSlices'),''));
  sel.value=id;active=id;
}
function loading(t){
  token=t;cards.clear();stamp='';mapMessage='';selection=-1;if(viewer)viewer.selected=-1;busy=true;error='';used=[];original=[];palette=[];details='';pathOK=false;plate='';sent='';mode='three';
  if(viewer){viewer.count=0;viewer.draw();}show();
}
async function loaded(data){
  if(data.token!==token)return;
  plate=data.plate||'';details=data.detail||'';original=data.colors||[];palette=[...original];error=data.error||'';
  if(data.paths && viewer){
    try{
      const r=await fetch(data.paths);if(!r.ok)throw Error('readFailed');
      const b=await r.arrayBuffer();if(data.token!==token)return;
      used=viewer.load(b);viewer.colors(palette);pathOK=true;
    }catch(e){error=e.message;}
  }
  if(data.token!==token)return;
  busy=false;if(!pathOK && plate)mode='plate';resetPhoto();show();if(pathOK)post('rendered',{token});else post('failed',{error:displayText(glError||error)});
}
function notice(text){mapMessage=text;show();}
function mapPending(text){cards.clear();stamp='';mapMessage=text;show();}
function mapFailed(text){cards.clear();stamp='';mapMessage=text;show();}
function mapped(data){
  if(data.token!==token)return;
  cards=new Map(data.cards.map(c=>[c.slot,c]));if(used.some(i=>!cards.has(i))){mapFailed('noMapping');return;}stamp=data.stamp;mapMessage='';mode='three';show();
}
function diff(a,b){
  if(!a||!b)return false;
  return [1,3,5].some(i=>Math.abs(parseInt(a.slice(i,i+2),16)-parseInt(b.slice(i,i+2),16))>15);
}
function actualColors(){return original.map((_,i)=>cards.get(i)?.color||'#a5afa8');}
function choose(i){selection=i===selection?-1:i;show();}
function resetPhoto(){photoScale=1;photoPan=[0,0];transformPhoto();}
function transformPhoto(){by('picture').style.transform='translate('+photoPan[0]+'px,'+photoPan[1]+'px) scale('+photoScale+')';}
function stampText(){return stamp?t(stamp.source,{date:stamp.date}):'';}
function filamentLabel(i,card){
  return t('filament',{id:i+1})+(card?' → '+t('slot',{id:card.tray}):'');
}
function show(){
  const three=is3d(),available=pathOK&&(mode==='design'||cards.size>0);
  by('gl').hidden=!three||!available;by('photo').hidden=three||!plate;
  if(!three&&plate&&by('picture').getAttribute('src')!==plate)by('picture').src=plate;
  by('actions').hidden=three?!available:!plate;
  const noData=displayText(glError||error)||t('start');
  by('empty').textContent=busy?t('loading'):three&&!pathOK?noData:mode==='three'&&!cards.size?t('readInstructions'):!three&&!plate?t('noPlate'):'';
  for(const b of document.querySelectorAll('[data-mode]'))b.setAttribute('aria-pressed',String(b.dataset.mode===mode));
  by('summary').textContent=displayText(details)||t('appName');
  by('hint').textContent=!busy&&three&&available?t('orbitHint'):mode==='plate'?t('photoHint'):'';
  const changes=[...cards.values()].filter(c=>diff(original[c.slot],c.color));
  const report=changes.length?t(changes.length===1?'checkingMismatch':'checkingMismatchPlural',{ids:changes.map(c=>c.slot+1).join(language==='en'?', ':'、')}):t('slotsRead');
  by('status').textContent=displayText(mapMessage)||(stamp?[stampText(),report,t(stamp.source==='live'?'autoRead':'reread')].join('  ·  '):'');
  const c=cards.get(selection);
  by('flag').hidden=!(three&&available&&selection>=0);
  by('flag').textContent=selection<0?'':filamentLabel(selection,c)+' · '+t('frame');
  by('colors').hidden=!three||!available;by('restore').hidden=selection<0;
  by('colorLabel').textContent=t(cards.size?'toAMS':'filaments');by('swatches').replaceChildren();
  for(const i of [...new Set([...used,...cards.keys()])].sort((a,b)=>a-b)){
    const c=cards.get(i),b=document.createElement('button');b.className='chip'+(c&&diff(original[i],c.color)?' changed':'');
    const dot=color=>{const d=document.createElement('span');d.className='dot';d.style.background=color||'#9eaaa3';return d;};
    b.title=filamentLabel(i,c)+(c?' · '+original[i]+' → '+c.color:'')+(used.includes(i)?'':t('unused'));
    b.append(document.createTextNode(i+1+' '),dot(original[i]));
    if(c)b.append(document.createTextNode('→'),dot(c.color),document.createTextNode(c.tray));
    b.setAttribute('aria-pressed',String(i===selection));b.disabled=!used.includes(i);b.onclick=()=>choose(i);by('swatches').append(b);
  }
  by('save').disabled=!cards.size||!pathOK;
  if(three&&available){viewer.selected=selection;viewer.colors(mode==='three'?actualColors():original);}
}
function zoom(factor){if(is3d()){if(!viewer)return;viewer.zoom=Math.min(30,Math.max(.15,viewer.zoom*factor));viewer.draw();}else{photoScale=Math.min(32,Math.max(.15,photoScale*factor));transformPhoto();}}
function reset(){if(is3d())viewer?.reset();else resetPhoto();}
by('open').onclick=()=>post('open');by('refresh').onclick=()=>post('refresh');by('capture').onclick=()=>post('ams');by('shot').onclick=()=>post('shot');by('save').onclick=()=>saveImage();
by('language').onchange=e=>{
  language=e.target.value;
  post('language',{value:language});
  localizeControls();
  setSources({list:sources,id:active});
  show();
};
by('sources').onchange=e=>post('select',{id:e.target.value});
for(const b of document.querySelectorAll('[data-mode]'))b.onclick=()=>{mode=b.dataset.mode;resetPhoto();show();};
by('full').onclick=()=>post('fullscreen');by('flag').onclick=()=>{if(!viewer.frameTool(selection))notice('occluded');};
by('minus').onclick=()=>zoom(1/1.25);by('plus').onclick=()=>zoom(1.25);by('home').onclick=reset;
by('restore').onclick=()=>{selection=-1;show();};
const stage=by('stage');let drag;
stage.onpointerdown=e=>{if(e.target.closest('button'))return;drag={ox:e.clientX,oy:e.clientY,x:e.clientX,y:e.clientY,pan:e.shiftKey||e.button!==0};stage.setPointerCapture(e.pointerId);};
stage.onpointermove=e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.x=e.clientX;drag.y=e.clientY;
  if(is3d()&&viewer){if(drag.pan){const s=1.74*viewer.radius/(viewer.zoom*Math.min(stage.clientHeight,stage.clientWidth));viewer.pan[0]-=dx*s;viewer.pan[1]+=dy*s;}else{viewer.az-=dx*.009;viewer.el=Math.max(-1.565,Math.min(1.565,viewer.el+dy*.009));}viewer.draw();}
  else{photoPan[0]+=dx;photoPan[1]+=dy;transformPhoto();}
};
stage.onpointerup=e=>{if(drag&&!drag.pan&&is3d()&&!by('gl').hidden&&Math.hypot(e.clientX-drag.ox,e.clientY-drag.oy)<4){const id=viewer.pick(e.clientX,e.clientY);if(id>=0)choose(id);}drag=null;};stage.onpointercancel=()=>drag=null;stage.oncontextmenu=e=>e.preventDefault();
stage.ondblclick=e=>{if(!e.target.closest('button'))reset();};
stage.addEventListener('wheel',e=>{e.preventDefault();zoom(Math.exp(-Math.max(-100,Math.min(100,e.deltaY))*(e.deltaMode===1?.08:.009)));},{passive:false});
let gesture=1;
stage.addEventListener('gesturestart',e=>{e.preventDefault();gesture=1;});
stage.addEventListener('gesturechange',e=>{e.preventDefault();zoom(e.scale/gesture);gesture=e.scale;});
new ResizeObserver(()=>viewer?.draw()).observe(stage);
function saveImage(options={}){
  const focus=options.focus??-1,single=options.single??(by('format').value==='one');
  if(!cards.size||!pathOK)return;
  const former=mode,sel=selection;mode='three';by('gl').hidden=false;
  const previousZoom=viewer.zoom,previousPan=[...viewer.pan];
  if(focus>=0){viewer.frameTool(focus);viewer.selected=-1;}else if(single&&viewer.zoom===1){viewer.zoom=1.30;}
  const out=document.createElement('canvas');out.width=single?2160:3840;out.height=single?3840:2160;
  const ctx=out.getContext('2d');ctx.fillStyle='#f3f5f1';ctx.fillRect(0,0,out.width,out.height);
  function text(str,x,y,size,color='#273c31',weight=450,maxWidth=out.width-x-60){ctx.fillStyle=color;ctx.font=weight+' '+size+'px -apple-system,BlinkMacSystemFont,sans-serif';ctx.fillText(str,x,y,maxWidth);}
  text(focus>=0?t('focusedTitle',{mapping:filamentLabel(focus,cards.get(focus))}):t('exportTitle'),80,104,68,'#233b2d',650);text(displayText(details),82,170,33);
  for(let i=single?1:0;i<2;i++){
    const x=single?60:60+i*1870,pw=single?2040:1840,ph=single?3030:1530;
    ctx.fillStyle=i?'#e5ede6':'#e9ede8';ctx.fillRect(x,208,pw,ph);
    text(t(i?'actualTitle':'designTitle'),x+48,304,55,'#273c31',650);
    viewer.colors(i?actualColors():original);viewer.paint(pw-40,ph-100);ctx.drawImage(viewer.canvas,x+20,308,pw-40,ph-100);
  }
  const legendY=single?3320:1818;
  text(stampText()+'    ·    '+t('legend'),80,legendY,39);
  const list=[...cards.values()].sort((a,b)=>a.slot-b.slot);
  const columns=single?Math.max(2,Math.ceil(list.length/4)):Math.max(4,Math.ceil(list.length/2)),col=(out.width-150)/columns;
  list.forEach((c,j)=>{
    const x=80+(j%columns)*col,y=legendY+42+Math.floor(j/columns)*100;
    const box=(xx,color)=>{ctx.fillStyle=color;ctx.fillRect(xx,y,56,48);ctx.strokeStyle='#819087';ctx.strokeRect(xx,y,56,48);};
    const font=Math.min(38,col*.075);
    text(t('filament',{id:c.slot+1}),x,y+40,font,'#273c31',450,col*.20);box(x+col*.22,original[c.slot]);text('→',x+col*.34,y+40,font);box(x+col*.44,c.color);
    text(t('slot',{id:c.tray}),x+col*.57,y+40,font,diff(original[c.slot],c.color)?'#894313':'#33483a',600);
  });
  viewer.zoom=previousZoom;viewer.pan=previousPan;viewer.selected=sel;selection=sel;mode=former;show();
  post('save',{png:out.toDataURL('image/png').split(',')[1]});
}
function openAbout() {
  const dialog=by('aboutPage');
  if (!dialog.open) dialog.showModal();
}
function closeAbout() {
  by('aboutPage').close();
}
by('aboutButton').onclick=openAbout;
localizeControls();show();post('ready');
