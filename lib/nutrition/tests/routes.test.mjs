import test from 'node:test';
import assert from 'node:assert/strict';
import { createNutritionAPI, NutritionRouteError } from '../routes.ts';
const config={apiKey:'synthetic-private-key',apiURL:'https://ai.example.test/v1/chat/completions',model:'test-model'};
const food={name:'Eggs',grams:100,kcal:144,protein:12,carbs:1,fat:10,confidence:.7};
const response=content=>Response.json({choices:[{message:{content:typeof content==='string'?content:JSON.stringify(content)}}]});
test('text, photo, exercise and review contracts are validated with typed output',async()=>{
 const seen=[];const api=createNutritionAPI(config,async(url,init)=>{seen.push({url,init});const body=JSON.parse(init.body),system=body.messages[0].content;return response(system.includes('Summarize ONLY')?{summary:'Your food log is incomplete.'}:system.includes('Estimate the described exercise energy')?{kcal:200}:{items:[food]});});
 assert.deepEqual(await api('/api/nutrition/parse-food',{text:'2 eggs'}),{items:[food]});
 assert.deepEqual(await api('/api/nutrition/analyze-meal',{image:'data:image/jpeg;base64,'+Buffer.from([255,216,255,1,2,3]).toString('base64')}),{items:[food]});
 assert.deepEqual(await api('/api/nutrition/estimate-exercise',{text:'30 min jogging',weightKg:80}),{kcal:200});
 assert.deepEqual(await api('/api/nutrition/day-review',{day:'2026-11-09',eaten:1000,protein:50,carbs:100,fat:20,exercise:0,goal:2000,estimatedBurned:2200,balance:1200,complete:false}),{summary:'Your food log is incomplete.'});
 assert.ok(seen.every(x=>x.init.headers.Authorization==='Bearer synthetic-private-key'&&x.init.redirect==='error'));assert.ok(seen.every(x=>x.url===config.apiURL));
});
test('invalid provider JSON retries exactly once and the second valid schema succeeds',async()=>{
 let calls=0;const api=createNutritionAPI(config,async()=>response(++calls===1?'not JSON':{items:[food]}));assert.deepEqual(await api('/api/nutrition/parse-food',{text:'eggs'}),{items:[food]});assert.equal(calls,2);
});
test('invalid values never bypass zod; two failures return a friendly redacted error',async()=>{
 let calls=0;const api=createNutritionAPI(config,async()=>{calls++;return response({items:[{...food,kcal:-10}]});});
 await assert.rejects(api('/api/nutrition/parse-food',{text:'eggs'}),e=>e instanceof NutritionRouteError&&e.status===502&&!e.message.includes(config.apiKey));assert.equal(calls,2);
});
test('missing keys do not contact any provider',async()=>{
 let calls=0;const api=createNutritionAPI({},async()=>{calls++;return response({items:[food]});});await assert.rejects(api('/api/nutrition/parse-food',{text:'eggs'}),e=>e.code==='ai_not_configured');assert.equal(calls,0);
});
test('HTTP rate limits and provider failures do not retry or expose their bodies',async()=>{
 for(const status of [401,429,500]){let calls=0;const api=createNutritionAPI(config,async()=>{calls++;return new Response('secret-provider-body',{status});});await assert.rejects(api('/api/nutrition/parse-food',{text:'eggs'}),e=>e.status===(status===429?429:503)&&!e.message.includes('secret'));assert.equal(calls,1);}
});
test('empty text, remote image URLs, invalid image headers and invalid weights are rejected before upstream access',async()=>{
 let calls=0;const api=createNutritionAPI(config,async()=>{calls++;return response({items:[food]});});
 for(const [path,body] of [['parse-food',{text:''}],['analyze-meal',{image:'https://remote.example/photo'}],['analyze-meal',{image:'data:image/jpeg;base64,YWJjZGVmZ2hp'}],['estimate-exercise',{text:'walk',weightKg:0}]])await assert.rejects(api('/api/nutrition/'+path,body),e=>e.status===400);
 assert.equal(calls,0);
});

test('review rejects impossible dates and negative energy totals before upstream access',async()=>{let calls=0;const api=createNutritionAPI(config,async()=>{calls++;return response({summary:'x'});});const base={day:'2026-11-09',eaten:1000,protein:1,carbs:1,fat:1,exercise:0,goal:2000,estimatedBurned:2200,balance:1200,complete:false};for(const body of [{...base,day:'2026-02-30'},{...base,goal:-1}])await assert.rejects(api('/api/nutrition/day-review',body),e=>e.status===400);assert.equal(calls,0);});
