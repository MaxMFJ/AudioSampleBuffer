/* Authoritative Canvas reference from 已粘贴的文本.txt.  Also used by the
 * golden-data generator; keep the arithmetic in this file deterministic. */
(function (root) {
  'use strict';
  const palette = ['#292036','#4d365e','#815d9c','#b085cd','#251b30','#dfbee8','#684979'];
  const pathCache = new Map();
  function rnd(n) { const x = Math.sin(n * 127.1 + 78.233) * 43758.5453; return x - Math.floor(x); }
  function makePath(i, W, H) {
    const seed = i * 23 + 11, angle = -Math.PI / 4, ux = Math.cos(angle), uy = Math.sin(angle), vx = -uy, vy = ux;
    const diagonal = 0.65 + rnd(i + 201) * 0.65;
    let x = -310 + rnd(seed) * W * 0.85, y = H * 0.65 + rnd(seed + 1) * H * 0.95;
    const pts = [[x,y]];
    const direction = i % 2 === 0 ? 1 : -1;
    for (let k=0;k<22;k++) {
      const f=(64+rnd(seed+k*5+3)*145)*diagonal; x+=ux*f; y+=uy*f; pts.push([x,y]);
      if(k<21){const s=(38+rnd(seed+k*5+4)*132)*(k%2===0?direction:-direction);x+=vx*s;y+=vy*s;pts.push([x,y]);}
    }
    const dist=[0]; for(let k=1;k<pts.length;k++)dist.push(dist[k-1]+Math.hypot(pts[k][0]-pts[k-1][0],pts[k][1]-pts[k-1][1]));
    return {id:i,pts,dist,total:dist[dist.length-1],diagonal};
  }
  function position(path,s){s=Math.max(0,Math.min(path.total,s));let j=1;while(j<path.dist.length-1&&path.dist[j]<s)j++;const d=path.dist[j]-path.dist[j-1]||1,a=(s-path.dist[j-1])/d;return{x:path.pts[j-1][0]*(1-a)+path.pts[j][0]*a,y:path.pts[j-1][1]*(1-a)+path.pts[j][1]*a,dx:(path.pts[j][0]-path.pts[j-1][0])/d,dy:(path.pts[j][1]-path.pts[j-1][1])/d};}
  function snapshot(time, opts) {
    opts=Object.assign({width:390,height:390,density:22,speed:1.2,trailLength:1.4,cameraTracking:0.75},opts);
    const W=opts.width,H=opts.height, cacheKey=`${W}x${H}`;
    if (!pathCache.has(cacheKey)) pathCache.set(cacheKey,Array.from({length:48},(_,i)=>makePath(i,W,H)));
    const paths=pathCache.get(cacheKey);
    const t=time, tracking=opts.cameraTracking, pulse=Math.pow(Math.max(0,Math.cos(t*5.2)),14), camProgress=t*260*tracking*0.53, shake=pulse*tracking*2.5, zoom=1+tracking*0.07+pulse*0.018, angle=-pulse*0.009*tracking;
    const arrows=[]; for(let i=0;i<Math.min(opts.density,paths.length);i++){const p=paths[i],r=rnd(i*9+7),head=(t*(150+r*180)+i*177)%(p.total+950),len=(330+r*450)*opts.trailLength,tail=Math.max(0,head-len), visibleEnd=Math.min(head,p.total); if(head<=tail||tail>=p.total)continue; const start=position(p,tail),end=position(p,visibleEnd), points=[[start.x,start.y]]; for(let j=1;j<p.dist.length-1;j++)if(p.dist[j]>tail&&p.dist[j]<visibleEnd)points.push(p.pts[j]); points.push([end.x,end.y]); const width=5+r*11+(i%7===0?7:0), a=Math.atan2(end.dy,end.dx),cs=Math.cos(a),sn=Math.sin(a),al=Math.max(20,width*3.1),wing=Math.max(13,width*1.7); arrows.push({id:i,head,tail,headPoint:end,width,color:palette[i%palette.length],highlight:i%8===0,points,tip:[[end.x+cs*al*.47,end.y+sn*al*.47],[end.x-cs*al*.5-sn*wing,end.y-sn*al*.5+cs*wing],[end.x-cs*al*.27,end.y-sn*al*.27],[end.x-cs*al*.5+sn*wing,end.y-sn*al*.5-cs*wing]]});}
    return {canvas:{width:W,height:H},config:{density:opts.density,speed:opts.speed,trailLength:opts.trailLength,cameraTracking:tracking},time,paths:opts.includePaths===false?undefined:paths.map(p=>({id:p.id,pts:p.pts,dist:p.dist,total:p.total,diagonal:p.diagonal})),arrows,cameraMatrix:{translate:[W*.5+Math.sin(t*25)*shake,H*.5+Math.cos(t*31)*shake],rotate:angle,scale:zoom,sceneTranslate:[-W*.5-0.7071067811865476*camProgress,-H*.5-(-0.7071067811865475)*camProgress]}};
  }
  root.VectorAssaultReference={rnd,makePath,position,snapshot,palette};
})(typeof window==='undefined'?globalThis:window);
