/** Single source for nutrition arithmetic, bundled unchanged for the native app. */
export type Meal = 'breakfast' | 'lunch' | 'dinner' | 'snack';
export type Units = 'metric' | 'imperial';
export interface Food { name: string; grams?: number; kcal: number; protein: number; carbs: number; fat: number; confidence?: number }
export interface FoodEntry { id: string; day: string; meal: Meal; food: Food; createdAt: string }
export interface Exercise { id: string; day: string; name: string; kcal: number; minutes?: number; estimated: boolean }
export interface Weight { id: string; day: string; value: number; unit: 'kg' | 'lb' }
export interface Favorite { id: string; food: Food }
export interface Settings {
  age?: number; sex: 'female' | 'male'; height?: number; weight?: number; units: Units;
  activity: 'sedentary' | 'light' | 'moderate' | 'active' | 'veryActive'; goal: 'lose' | 'maintain' | 'gain';
  maintenanceOverride?: number; calorieOverride?: number; proteinOverride?: number; carbsOverride?: number; fatOverride?: number;
}
export interface NutritionData { foods: FoodEntry[]; exercises: Exercise[]; weights: Weight[]; favorites: Favorite[]; completedDays: string[]; settings: Settings }
export interface CalcRequest { day: string; data: NutritionData }
export interface Goals { maintenance: number | null; calories: number | null; protein: number | null; carbs: number | null; fat: number | null; weightKg: number | null }
export interface Totals { eaten: number; exercise: number; protein: number; carbs: number; fat: number; estimatedBurned: number | null; balance: number | null; fatChangeKg: number | null }
export interface DayPoint { day: string; eaten: number | null; protein: number | null; balance: number | null; goal: number | null; completed: boolean }
export interface WeightPoint { day: string; value: number; trend: number }
export interface Dial { value: number | null; target: number | null; fraction: number; status: 'progress' | 'target' | 'close' | 'over' }
export interface Calculation {
  day: string; goals: Goals; totals: Totals; meals: { meal: Meal; kcal: number; protein: number; carbs: number; fat: number }[];
  series: DayPoint[]; averageEaten: number | null; averages: { range: number; eaten: number | null; protein: number | null }[]; loggedDays: number; completeDays: number;
  weeklyBalance: number | null; weeklyFatChangeKg: number | null; loggingStreak: number;
  weightSeries: WeightPoint[]; weightUnit: 'kg' | 'lb'; latestWeight: number | null;
  caloriesDial: Dial; proteinDial: Dial; carbsDial: Dial; fatDial: Dial; netDial: Dial; hasLog: boolean; isComplete: boolean;
}
const meals: Meal[] = ['breakfast', 'lunch', 'dinner', 'snack'];
const factors = { sedentary: 1.2, light: 1.375, moderate: 1.55, active: 1.725, veryActive: 1.9 };
const record = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const fail = (message: string): never => { throw new Error(message); };
const bounded = (v: unknown, min: number, max: number): v is number => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
const text = (v: unknown): v is string => typeof v === 'string' && v.trim().length > 0 && v.length <= 120 && !/[\u0000-\u001f]/.test(v);
function validDay(v: unknown): v is string {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
  const time = Date.parse(v + 'T00:00:00Z');
  return Number.isFinite(time) && v >= '1900-01-01' && v <= '2100-12-31' && new Date(time).toISOString().slice(0, 10) === v;
}
function food(v: unknown): v is Food {
  return record(v) && text(v.name) && bounded(v.kcal, 0, 20_000) && ['protein', 'carbs', 'fat'].every(k => bounded(v[k], 0, 2_000)) &&
    (v.grams === undefined || bounded(v.grams, 0.1, 10_000)) && (v.confidence === undefined || bounded(v.confidence, 0, 1));
}
function validate(input: CalcRequest): void {
  if (!record(input) || !validDay(input.day) || !record(input.data)) fail('Choose a valid nutrition date.');
  const d = input.data;
  const collections = [d.foods, d.exercises, d.weights, d.favorites, d.completedDays];
  if (collections.some(a => !Array.isArray(a)) || collections.reduce((n, a) => n + a.length, 0) > 10_000) fail('Nutrition storage supports at most 10,000 records. Export and archive older data first.');
  for (const a of [d.foods, d.exercises, d.weights, d.favorites]) {
    const ids = new Set<string>();
    for (const item of a) { if (!record(item) || !text(item.id) || ids.has(item.id)) fail('Nutrition record identities conflict.'); ids.add(item.id); }
  }
  if (d.foods.some(f => !validDay(f.day) || !meals.includes(f.meal) || !food(f.food) || !Number.isFinite(Date.parse(f.createdAt)))) fail('Check food names, dates, calories and macros.');
  if (d.favorites.some(f => !food(f.food))) fail('A favorite food is invalid.');
  if (d.exercises.some(e => !validDay(e.day) || !text(e.name) || !bounded(e.kcal, 0, 20_000) || typeof e.estimated !== 'boolean' || (e.minutes !== undefined && !bounded(e.minutes, 1, 1_440)))) fail('Check exercise names, dates and calories.');
  const days = new Set<string>();
  for (const w of d.weights) {
    if (!validDay(w.day) || days.has(w.day) || !['kg', 'lb'].includes(w.unit) || !bounded(w.value, 1, 1_500) || !bounded(w.unit === 'lb' ? w.value / 2.20462262185 : w.value, 20, 400)) fail('Keep one weight per day, between 20 and 400 kg (or equivalent pounds).');
    days.add(w.day);
  }
  if (d.completedDays.some(d => !validDay(d)) || new Set(d.completedDays).size !== d.completedDays.length) fail('Completed nutrition dates are invalid.');
  const s = d.settings;
  if (!record(s) || !['female', 'male'].includes(s.sex) || !['metric', 'imperial'].includes(s.units) || !Object.hasOwn(factors, s.activity) || !['lose', 'maintain', 'gain'].includes(s.goal)) fail('Choose valid nutrition settings.');
  if ((s.age !== undefined && (!bounded(s.age, 18, 100) || !Number.isInteger(s.age))) ||
      (s.height !== undefined && !bounded(s.units === 'imperial' ? s.height * 2.54 : s.height, 80, 250)) ||
      (s.weight !== undefined && !bounded(s.units === 'imperial' ? s.weight / 2.20462262185 : s.weight, 20, 400))) fail('Auto targets support ages 18–100, heights 80–250 cm and weights 20–400 kg.');
  for (const v of [s.maintenanceOverride, s.calorieOverride]) if (v !== undefined && !bounded(v, 1_000, 10_000)) fail('Manual energy targets must be between 1,000 and 10,000 kcal.');
  for (const v of [s.proteinOverride, s.carbsOverride, s.fatOverride]) if (v !== undefined && !bounded(v, 0, 2_000)) fail('Manual macro targets must be between 0 and 2,000 grams.');
}
const shifted = (day: string, count: number): string => new Date(Date.parse(day + 'T00:00:00Z') + count * 86_400_000).toISOString().slice(0, 10);
const rounded = (v: number): number => Math.round(v * 100) / 100;
function targets(s: Settings, weights: Weight[], day: string): Goals {
  const latest = weights.filter(w => w.day <= day).sort((a, b) => a.day.localeCompare(b.day)).at(-1);
  const weightKg = latest ? (latest.unit === 'lb' ? latest.value / 2.20462262185 : latest.value) : s.weight === undefined ? null : s.units === 'imperial' ? s.weight / 2.20462262185 : s.weight;
  const heightCm = s.height === undefined ? null : s.units === 'imperial' ? s.height * 2.54 : s.height;
  let maintenance = s.maintenanceOverride ?? (s.age !== undefined && heightCm !== null && weightKg !== null ?
    (10 * weightKg + 6.25 * heightCm - 5 * s.age + (s.sex === 'male' ? 5 : -161)) * factors[s.activity] : null);
  if (maintenance !== null) { if (!Number.isFinite(maintenance) || maintenance <= 0 || maintenance > 10_000) fail('Calculated maintenance is outside the supported range. Set a manual override.'); maintenance = Math.round(maintenance); }
  const proposed = maintenance === null ? null : maintenance + (s.goal === 'lose' ? -500 : s.goal === 'gain' ? 300 : 0);
  const calories = s.calorieOverride ?? proposed;
  if (calories !== null && (calories < 1_000 || calories > 10_000)) fail('Calculated calorie goal is outside 1,000–10,000 kcal. Review your profile or set a manual goal.');
  return { maintenance, calories, weightKg: weightKg === null ? null : rounded(weightKg),
    protein: s.proteinOverride ?? (calories === null ? null : Math.round(calories * .3 / 4)),
    carbs: s.carbsOverride ?? (calories === null ? null : Math.round(calories * .4 / 4)),
    fat: s.fatOverride ?? (calories === null ? null : Math.round(calories * .3 / 9)) };
}
function totals(d: NutritionData, day: string, g: Goals): Totals {
  const values = d.foods.filter(f => f.day === day).reduce((sum, item) => ({ eaten: sum.eaten + item.food.kcal, protein: sum.protein + item.food.protein, carbs: sum.carbs + item.food.carbs, fat: sum.fat + item.food.fat }), { eaten: 0, protein: 0, carbs: 0, fat: 0 });
  const exercise = d.exercises.filter(e => e.day === day).reduce((n, e) => n + e.kcal, 0);
  const estimatedBurned = g.maintenance === null ? null : g.maintenance + exercise;
  const hasLog = d.foods.some(f => f.day === day) || d.exercises.some(e => e.day === day) || d.completedDays.includes(day);
  const balance = estimatedBurned === null || !hasLog ? null : estimatedBurned - values.eaten;
  return { eaten: rounded(values.eaten), protein: rounded(values.protein), carbs: rounded(values.carbs), fat: rounded(values.fat), exercise: rounded(exercise), estimatedBurned, balance: balance === null ? null : rounded(balance), fatChangeKg: balance === null ? null : -balance / 7_700 };
}
function dial(value: number | null, target: number | null): Dial {
  if (value !== null && target === 0) return { value, target, fraction: value > 0 ? 1 : 0, status: value > 0 ? 'over' : 'target' };
  const ratio = value === null || target === null || target <= 0 ? 0 : value / target;
  return { value, target, fraction: Math.min(1, Math.max(0, ratio)), status: value === null || target === null ? 'progress' : value > target ? 'over' : ratio >= .9 ? 'target' : ratio >= .75 ? 'close' : 'progress' };
}
export function calculateNutrition(input: CalcRequest): Calculation {
  validate(input);
  const { data: d, day } = input, g = targets(d.settings, d.weights, day), t = totals(d, day, g);
  const series: DayPoint[] = Array.from({ length: 30 }, (_, i) => {
    const key = shifted(day, i - 29), gt = targets(d.settings, d.weights, key), dt = totals(d, key, gt), completed = d.completedDays.includes(key);
    return { day: key, eaten: d.foods.some(f => f.day === key) || completed ? dt.eaten : null, protein: d.foods.some(f => f.day === key) || completed ? dt.protein : null, balance: completed ? dt.balance : null, goal: gt.calories, completed };
  });
  const logged = series.flatMap(p => p.eaten === null ? [] : [p.eaten]);
  const weekly = series.slice(-7).flatMap(p => p.balance === null ? [] : [p.balance]);
  const sumBalance = weekly.length ? rounded(weekly.reduce((n, v) => n + v, 0)) : null;
  const loggedDates = new Set(d.foods.map(f => f.day)); let cursor = loggedDates.has(day) ? day : shifted(day, -1), streak = 0;
  while (loggedDates.has(cursor)) { streak++; cursor = shifted(cursor, -1); }
  const unit = d.settings.units === 'imperial' ? 'lb' : 'kg';
  const weights = d.weights.filter(w => w.day <= day).sort((a, b) => a.day.localeCompare(b.day));
  const normalized = weights.map(w => ({ day: w.day, kg: w.unit === 'lb' ? w.value / 2.20462262185 : w.value }));
  const weightSeries = normalized.filter(w => w.day >= shifted(day, -29)).map(w => {
    const window = normalized.filter(x => x.day >= shifted(w.day, -6) && x.day <= w.day);
    const mean = window.reduce((n, x) => n + x.kg, 0) / window.length;
    return { day: w.day, value: rounded(unit === 'lb' ? w.kg * 2.20462262185 : w.kg), trend: rounded(unit === 'lb' ? mean * 2.20462262185 : mean) };
  });
  const latest = normalized.at(-1)?.kg;
  const caloriesDial = dial(t.eaten, g.calories);
  caloriesDial.value = g.calories === null ? null : rounded(g.calories - t.eaten);
  const netTarget = g.maintenance === null || g.calories === null ? null : g.maintenance - g.calories;
  const netDial = dial(t.balance === null ? null : Math.abs(t.balance), netTarget === null ? null : Math.max(100, Math.abs(netTarget)));
  if (t.balance !== null) netDial.status = d.settings.goal === 'lose' ? (t.balance >= 0 ? 'target' : 'over') : d.settings.goal === 'gain' ? (t.balance <= 0 ? 'target' : 'close') : Math.abs(t.balance) <= 100 ? 'target' : Math.abs(t.balance) <= 300 ? 'close' : 'over';
  return { day, goals: g, totals: t, meals: meals.map(meal => {
    const rows = d.foods.filter(f => f.day === day && f.meal === meal);
    return { meal, kcal: rounded(rows.reduce((n, f) => n + f.food.kcal, 0)), protein: rounded(rows.reduce((n, f) => n + f.food.protein, 0)), carbs: rounded(rows.reduce((n, f) => n + f.food.carbs, 0)), fat: rounded(rows.reduce((n, f) => n + f.food.fat, 0)) };
  }), series, averageEaten: logged.length ? rounded(logged.reduce((n, v) => n + v, 0) / logged.length) : null,
    averages: [7, 30].map(range => {
      const points = series.slice(-range), intake = points.flatMap(p => p.eaten === null ? [] : [p.eaten]), proteins = points.flatMap(p => p.protein === null ? [] : [p.protein]);
      return { range, eaten: intake.length ? rounded(intake.reduce((n,v) => n+v,0)/intake.length) : null, protein: proteins.length ? rounded(proteins.reduce((n,v) => n+v,0)/proteins.length) : null };
    }), loggedDays: logged.length, completeDays: series.filter(p => p.completed).length, weeklyBalance: sumBalance,
    weeklyFatChangeKg: sumBalance === null ? null : -sumBalance / 7_700, loggingStreak: streak, weightSeries, weightUnit: unit,
    latestWeight: latest === undefined ? null : rounded(unit === 'lb' ? latest * 2.20462262185 : latest),
    caloriesDial, proteinDial: dial(t.protein, g.protein), carbsDial: dial(t.carbs, g.carbs), fatDial: dial(t.fat, g.fat), netDial,
    hasLog: d.foods.some(f => f.day === day) || d.exercises.some(e => e.day === day), isComplete: d.completedDays.includes(day) };
}
