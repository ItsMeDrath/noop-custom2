import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { calculateNutrition } from '../calc.ts';
const day='2026-11-09';
const settings={age:30,sex:'male',height:180,weight:80,units:'metric',activity:'sedentary',goal:'maintain'};
const state=()=>({foods:[],exercises:[],weights:[],favorites:[],completedDays:[],settings:{...settings}});
const entry=(kcal=500,key=day,id='food')=>({id,day:key,meal:'breakfast',food:{name:'Meal',kcal,protein:25,carbs:40,fat:12},createdAt:key+'T12:00:00.000Z'});
const calc=data=>calculateNutrition({day,data});
test('Mifflin–St Jeor, sex coefficient, activity and goal offsets are explicit',()=>{
 const d=state();assert.equal(calc(d).goals.maintenance,2136);d.settings.sex='female';assert.equal(calc(d).goals.maintenance,1937);
 d.settings={...settings,goal:'lose'};assert.equal(calc(d).goals.calories,1636);d.settings.goal='gain';assert.equal(calc(d).goals.calories,2436);
 d.settings.activity='moderate';assert.equal(calc(d).goals.maintenance,2759);
});
test('imperial profile and later weight logs normalize before target calculation',()=>{
 const d=state();d.settings={...settings,units:'imperial',height:180/2.54,weight:80*2.20462262185};assert.equal(calc(d).goals.maintenance,2136);
 d.weights=[{id:'w',day,value:90,unit:'kg'}];assert.equal(calc(d).goals.weightKg,90);assert.equal(calc(d).latestWeight,198.42);
});
test('manual overrides work without a profile and macro percentages are calculated centrally',()=>{
 const d=state();d.settings={sex:'female',units:'metric',activity:'light',goal:'maintain',calorieOverride:2000,proteinOverride:123};const c=calc(d);
 assert.equal(c.goals.maintenance,null);assert.equal(c.goals.calories,2000);assert.equal(c.goals.protein,123);assert.equal(c.goals.carbs,200);assert.equal(c.goals.fat,67);
});
test('unlogged days never fabricate deficits, fat changes or averages',()=>{
 const c=calc(state());assert.equal(c.totals.balance,null);assert.equal(c.totals.fatChangeKg,null);assert.equal(c.weeklyBalance,null);assert.equal(c.averageEaten,null);assert.ok(c.series.every(p=>p.eaten===null&&p.balance===null));
});
test('meal totals, exercise and 7700-kcal energy equivalent use only matching dates',()=>{
 const d=state();d.foods=[entry(500),entry(300,day,'second'),entry(9999,'2026-11-08','previous')];d.exercises=[{id:'e',day,name:'Walk',kcal:164,estimated:false}];const c=calc(d);
 assert.equal(c.totals.eaten,800);assert.equal(c.totals.protein,50);assert.equal(c.totals.estimatedBurned,2300);assert.equal(c.totals.balance,1500);assert.equal(c.totals.fatChangeKg,-1500/7700);assert.equal(c.meals[0].kcal,800);assert.equal(c.meals[1].kcal,0);
});
test('weekly totals include completed days only; incomplete eating still appears on intake chart',()=>{
 const d=state();d.foods=[entry(500),entry(700,'2026-11-08','other')];let c=calc(d);assert.equal(c.weeklyBalance,null);assert.equal(c.averageEaten,600);
 d.completedDays=['2026-11-08'];c=calc(d);assert.equal(c.weeklyBalance,1436);assert.equal(c.weeklyFatChangeKg,-1436/7700);assert.equal(c.completeDays,1);
});
test('7/30-day averages ignore missing logs; protein chart uses actual totals',()=>{
 const d=state();d.foods=[entry(600),entry(1000,'2026-10-25','old')];const c=calc(d);
 assert.deepEqual(c.averages,[{range:7,eaten:600,protein:25},{range:30,eaten:800,protein:25}]);assert.equal(c.series.at(-1).protein,25);
});
test('logging streak deduplicates same-day foods and stops at calendar gaps',()=>{
 const d=state();d.foods=[entry(1,day,'a'),entry(1,day,'b'),entry(1,'2026-11-08','c'),entry(1,'2026-11-06','d')];assert.equal(calc(d).loggingStreak,2);
 d.foods=d.foods.filter(f=>f.day!==day);assert.equal(calc(d).loggingStreak,1);
});
test('rolling weight averages use seven calendar days and retain recorded dates',()=>{
 const d=state();d.weights=[{id:'a',day:'2026-10-01',value:100,unit:'kg'},{id:'b',day:'2026-11-08',value:80,unit:'kg'},{id:'c',day,value:82,unit:'kg'}];const c=calc(d);
 assert.equal(c.weightSeries.length,2);assert.equal(c.weightSeries.at(-1).trend,81);assert.equal(c.latestWeight,82);
});
test('malformed dates, duplicate IDs, unsupported ranges and nonfinite values fail before calculation',()=>{
 for(const edit of [d=>d.foods=[entry(-1)],d=>d.foods=[entry(Infinity)],d=>d.foods=[entry(5),entry(5)],d=>d.foods=[entry(5,'2026-02-30')],d=>d.settings.age=17,d=>d.settings.activity='toString',d=>d.settings.height=900,d=>d.weights=[{id:'x',day,value:1,unit:'kg'}],d=>d.completedDays=[day,day]]){const d=state();edit(d);assert.throws(()=>calc(d));}
});
test('dial fill is bounded; status text accompanies over-target values',()=>{
 const d=state();d.foods=[entry(3000)];const c=calc(d);assert.equal(c.caloriesDial.value,-864);assert.equal(c.caloriesDial.fraction,1);assert.equal(c.caloriesDial.status,'over');assert.equal(c.netDial.status,'over');
});
test('generated offline native bundle produces exactly the canonical response',async()=>{
 const d=state();d.foods=[entry()];const context=vm.createContext({});vm.runInContext(await readFile(new URL('../../../App/Resources/nutrition-calc.js',import.meta.url),'utf8'),context);
 assert.deepEqual(JSON.parse(context.NutritionCalc.calculate(JSON.stringify({day,data:d}))),calc(d));
});

test('zero manual macro targets are valid and over-target fill stays truthful',()=>{const d=state();d.settings.proteinOverride=0;let c=calc(d);assert.equal(c.proteinDial.status,'target');d.foods=[entry()];c=calc(d);assert.equal(c.proteinDial.status,'over');assert.equal(c.proteinDial.fraction,1);});
