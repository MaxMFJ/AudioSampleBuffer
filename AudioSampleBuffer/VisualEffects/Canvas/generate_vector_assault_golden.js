#!/usr/bin/env node
const fs=require('fs'),path=require('path'),vm=require('vm');
const src=fs.readFileSync(path.join(__dirname,'vector_assault_reference.js'),'utf8'); const ctx={}; vm.runInNewContext(src,ctx);
const samples=[0.5,1,2,3].map(time=>ctx.VectorAssaultReference.snapshot(time));
const out=path.join(__dirname,'vector_assault_golden.json'); fs.writeFileSync(out,JSON.stringify({schema:'vector-assault-canvas-reference-v1',provenance:'已粘贴的文本.txt; exact reference algorithm',samples},null,2)+'\n'); console.log(out);
