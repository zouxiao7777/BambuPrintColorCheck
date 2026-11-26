// Render one rounded extrusion per instance. Coordinates stay in millimetres.
class PathViewer {
  constructor(canvas) {
    this.canvas=canvas;
    const g=this.g=canvas.getContext('webgl2',{alpha:true,antialias:true});
    if(!g) throw Error('webglFailed');
    const vs=`#version 300 es
      precision highp float;
      layout(location=0) in vec3 start;
      layout(location=1) in vec3 finish;
      layout(location=2) in vec3 bead;
      uniform vec3 target,right,up,eye;
      uniform vec2 scale;
      uniform float depth;
      out vec3 normal;
      flat out int slot;
      void main(){
        vec3 dir=normalize(finish-start);
        vec3 side=normalize(vec3(-dir.y,dir.x,0.0));
        vec3 vertical=normalize(cross(dir,side));
        float angle=float(gl_VertexID/2)*1.04719755;
        float c=cos(angle),s=sin(angle);
        bool endp=(gl_VertexID%2)==1;
        vec3 p=(endp?finish:start)+side*c*bead.x*.5+vertical*s*bead.y*.5;
        p+=dir*(endp?1.0:-1.0)*min(bead.x*.10,length(finish-start)*.12);
        p.z-=bead.y*.5;
        vec3 local=p-target;
        gl_Position=vec4(dot(local,right)*scale.x,dot(local,up)*scale.y,-dot(local,eye)/depth,1.0);
        normal=normalize(side*c+vertical*s);slot=int(bead.z+0.5);
      }`;
    const fs=`#version 300 es
      precision highp float;
      precision highp int;
      in vec3 normal;
      flat in int slot;
      uniform sampler2D palette;
      uniform vec3 light;
      uniform int selected,picking;
      out vec4 frag;
      void main(){
        if(picking==1){frag=vec4(vec3(float(slot+1),float((slot*83+29)%251),float((slot*191+47)%253))/255.,1.);return;}
        vec3 base=texelFetch(palette,ivec2(slot,0),0).rgb;
        float diffuse=.72+.28*max(0.0,dot(normalize(normal),light));
        base=max(base,vec3(.13));vec3 color=base*diffuse+vec3(.018)*max(0.,dot(normalize(normal),light));
        if(selected>=0 && selected!=slot)color=mix(vec3(.82,.84,.83),vec3(dot(color,vec3(.3,.59,.11))),.10);
        frag=vec4(color,1.0);
      }`;
    const prog=g.createProgram();
    for(const [type,source] of [[g.VERTEX_SHADER,vs],[g.FRAGMENT_SHADER,fs]]){
      const shader=g.createShader(type);g.shaderSource(shader,source);g.compileShader(shader);
      if(!g.getShaderParameter(shader,g.COMPILE_STATUS))throw Error(g.getShaderInfoLog(shader));
      g.attachShader(prog,shader);
    }
    g.linkProgram(prog);if(!g.getProgramParameter(prog,g.LINK_STATUS))throw Error(g.getProgramInfoLog(prog));
    g.useProgram(prog);this.uniform={};
    for(const k of ['target','right','up','eye','scale','depth','light','palette','selected','picking'])this.uniform[k]=g.getUniformLocation(prog,k);
    this.buf=g.createBuffer();g.bindBuffer(g.ARRAY_BUFFER,this.buf);
    for(let i=0;i<3;i++){g.enableVertexAttribArray(i);g.vertexAttribPointer(i,3,g.FLOAT,false,36,12*i);g.vertexAttribDivisor(i,1);}
    g.enable(g.DEPTH_TEST);g.clearColor(0,0,0,0);
    this.tex=g.createTexture();g.bindTexture(g.TEXTURE_2D,this.tex);
    g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MIN_FILTER,g.NEAREST);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MAG_FILTER,g.NEAREST);
    this.pickFB=g.createFramebuffer();this.pickColor=g.createRenderbuffer();this.pickDepth=g.createRenderbuffer();this.pickSize=[0,0];this.bounds=new Map();
    this.selected=-1;this.count=0;this.radius=1;this.center=[0,0,0];this.reset();
  }
  load(buffer){
    if(buffer.byteLength%36)throw Error('incomplete');
    const a=new Float32Array(buffer),lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity],slots=new Set();
    if(!a.length) throw Error('noPaths');
    this.bounds.clear();
    for(let i=0;i<a.length;i+=9){
      const id=a[i+8];let b=this.bounds.get(id);
      if(!b){b=[Infinity,Infinity,Infinity,-Infinity,-Infinity,-Infinity];this.bounds.set(id,b);}
      for(let j=0;j<3;j++){const min=Math.min(a[i+j],a[i+3+j]),max=Math.max(a[i+j],a[i+3+j]);lo[j]=Math.min(lo[j],min);hi[j]=Math.max(hi[j],max);b[j]=Math.min(b[j],min);b[j+3]=Math.max(b[j+3],max);}
      slots.add(id);
    }
    this.center=lo.map((x,i)=>(x+hi[i])/2);this.radius=Math.max(1,Math.hypot(...hi.map((x,i)=>x-lo[i]))/2);
    this.count=a.length/9;this.g.bufferData(this.g.ARRAY_BUFFER,a,this.g.STATIC_DRAW);this.reset();
    return [...slots].sort((a,b)=>a-b);
  }
  colors(list){
    const table=new Uint8Array(256*4);
    for(let i=0;i<256;i++){const s=(list[i]||'#9eaaa3').slice(1);for(let c=0;c<3;c++)table[i*4+c]=parseInt(s.slice(c*2,c*2+2),16);table[i*4+3]=255;}
    const g=this.g;g.texImage2D(g.TEXTURE_2D,0,g.RGBA,256,1,0,g.RGBA,g.UNSIGNED_BYTE,table);this.draw();
  }
  reset(){this.az=-1.17;this.el=.30;this.zoom=1;this.pan=[0,0];this.draw();}
  draw(){
    if(this.scheduled)return;
    this.scheduled=true;requestAnimationFrame(()=>{this.scheduled=false;this.paint();});
  }
  frameTool(id){
    const bounds=this.bounds.get(id);if(!bounds)return false;
    const ca=Math.cos(this.az),sa=Math.sin(this.az),ce=Math.cos(this.el),se=Math.sin(this.el);
    const basis=[[-sa,ca,0],[-ca*se,-sa*se,ce]];
    const center=[0,1,2].map(i=>(bounds[i]+bounds[i+3])/2-this.center[i]);
    const size=[0,1,2].map(i=>bounds[i+3]-bounds[i]);
    this.pan=basis.map(v=>v.reduce((s,c,i)=>s+c*center[i],0));
    const span=Math.max(...basis.map(v=>v.reduce((s,c,i)=>s+Math.abs(c)*size[i],0)));
    this.zoom=Math.max(1,Math.min(10,this.radius*1.42/Math.max(1,span)));this.draw();return true;
  }
  pick(x,y){
    const c=this.canvas,b=c.getBoundingClientRect(),g=this.g,out=new Uint8Array(4);
    this.paint(undefined,undefined,true);
    g.readPixels(Math.min(c.width-1,Math.floor((x-b.left)/b.width*c.width)),Math.min(c.height-1,Math.floor((b.bottom-y)/b.height*c.height)),1,1,g.RGBA,g.UNSIGNED_BYTE,out);
    g.bindFramebuffer(g.FRAMEBUFFER,null);this.draw();const id=out[0]-1;return out[3]===255 && out[1]===(id*83+29)%251 && out[2]===(id*191+47)%253?id:-1;
  }
  paint(forceW,forceH,picking=false){
    const g=this.g,c=this.canvas;if(!c.clientWidth||!c.clientHeight)return;
    const dpr=Math.min(window.devicePixelRatio||1,2),w=forceW||Math.round(c.clientWidth*dpr),h=forceH||Math.round(c.clientHeight*dpr);
    if(c.width!==w||c.height!==h){c.width=w;c.height=h;}g.bindFramebuffer(g.FRAMEBUFFER,picking?this.pickFB:null);
    if(picking&&(this.pickSize[0]!==w||this.pickSize[1]!==h)){
      for(const [rb,format,point] of [[this.pickColor,g.RGBA8,g.COLOR_ATTACHMENT0],[this.pickDepth,g.DEPTH_COMPONENT16,g.DEPTH_ATTACHMENT]]){
        g.bindRenderbuffer(g.RENDERBUFFER,rb);g.renderbufferStorage(g.RENDERBUFFER,format,w,h);g.framebufferRenderbuffer(g.FRAMEBUFFER,point,g.RENDERBUFFER,rb);
      }
      this.pickSize=[w,h];
    }
    if(picking)g.disable(g.DITHER);else g.enable(g.DITHER);
    g.viewport(0,0,w,h);g.clear(g.COLOR_BUFFER_BIT|g.DEPTH_BUFFER_BIT);if(!this.count)return;
    const ca=Math.cos(this.az),sa=Math.sin(this.az),ce=Math.cos(this.el),se=Math.sin(this.el);
    const right=[-sa,ca,0],up=[-ca*se,-sa*se,ce],eye=[ca*ce,sa*ce,se];
    const target=this.center.map((v,i)=>v+right[i]*this.pan[0]+up[i]*this.pan[1]);
    const unit=this.radius*.88/this.zoom,aspect=w/h;
    for(const [k,v] of Object.entries({target,right,up,eye,light:[-.35,-.48,.804]}))g.uniform3fv(this.uniform[k],v);
    g.uniform2f(this.uniform.scale,1/(unit*Math.max(1,aspect)),1/(unit*Math.max(1,1/aspect)));
    g.uniform1i(this.uniform.selected,this.selected);g.uniform1i(this.uniform.picking,picking?1:0);
    g.uniform1f(this.uniform.depth,Math.max(10,this.radius*2));g.drawArraysInstanced(g.TRIANGLE_STRIP,0,14,this.count);
  }
}
