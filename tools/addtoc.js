// usage: node addtoc.js <after-line-substring> <new entries...>
const fs=require('fs');const p='../XerionUI/XerionUI.toc';let s=fs.readFileSync(p,'utf8');
const nl=s.includes('\r\n')?'\r\n':'\n';const lines=s.split(/\r?\n/);
const [after,...add]=process.argv.slice(2);
const i=lines.findIndex(l=>l.includes(after));if(i<0)throw new Error('no '+after);
const have=new Set(lines);const fresh=add.filter(a=>!have.has(a));
lines.splice(i+1,0,...fresh);fs.writeFileSync(p,lines.join(nl));
