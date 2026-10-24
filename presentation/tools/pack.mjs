import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const files={today:'today.webp',practice:'practice.webp',progress:'progress.webp',speak:'speak.webp',tremor:'tremor.webp',voice:'voice.webp',onboarding:'onboarding.webp',todayClip:'today.mp4',tremorClip:'tremor.mp4',voiceClip:'voice.mp4'};
const assets={};for(const [name,file]of Object.entries(files)){const b=await readFile(path.join(root,'assets',file));assets[name]=`data:${file.endsWith('mp4')?'video/mp4':'image/webp'};base64,${b.toString('base64')}`}
const html=(await readFile(path.join(root,'animation.template.html'),'utf8')).replace('/*__ASSETS__*/{}',JSON.stringify(assets));await writeFile(path.join(root,'animation.html'),html);console.log(`Packed self-contained animation: ${(Buffer.byteLength(html)/1024/1024).toFixed(2)} MB`);
