/**
 * Pondlife v3.1 — fullscreen + auto generators + rate sliders + evolutionary splits
 * MOUSE:
 *   LEFT  = paint nutrients (visible ripple)
 *   RIGHT = shockwave (or hold SHIFT+LEFT)
 *
 * KEYS:
 *   G = toggle overlays (grid/fields)
 *   F = toggle animated flow
 *   X = toggle fullscreen
 *   E = toggle evolution (splitting)
 *   1 = spawn herbivores at mouse
 *   2 = spawn predators at mouse
 *   C = clear all fields/agents
 *
 * SLIDERS (bottom-left):
 *   Auto Food Rate (deposits/sec)
 *   Herbivore Spawn (per sec)
 *   Predator Spawn (per sec)
 * By: Mohammad Elzein 08/18/2025
 */

ArrayList<Herbivore> herbivores = new ArrayList<Herbivore>();
ArrayList<Predator>  predators  = new ArrayList<Predator>();
ArrayList<Ripple>    ripples    = new ArrayList<Ripple>();

NutrientField nutrients;
ScentField    herbivoreScent;
FlowField     flow;

boolean showFields  = false;
boolean animateFlow = true;
boolean isFullscreen = false;

// --- Evolution toggles & goals ---
boolean evolutionOn = true;         // toggle with 'E'
final float HERB_GOAL_INTAKE = 5.0; // nutrients accumulated since last split (tune)
final int   PRED_GOAL_KILLS  = 6;   // kills since last split (tune)

// soft caps (safety against runaway growth)
final int MAX_HERB = 1800;
final int MAX_PRED = 500;

int   CELL    = 10;
float BG_FADE = 20;

// UI sliders
Slider sFood, sHerbRate, sPredRate;
float uiMargin = 12;
float hudH = 26;

// timekeeping for auto generators
int lastMillis = 0;
float accFood = 0, accHerb = 0, accPred = 0;

// remember windowed size when toggling fullscreen
int winW = 1000, winH = 700;

void settings() {
  size(winW, winH, P2D);
  smooth(4);
  pixelDensity(1);

}

void setup() {
  colorMode(HSB, 360, 100, 100, 100);
  frameRate(60);
   surface.setLocation(500,500);
  surface.setResizable(true);

  buildFields(width, height);

  // Seed initial population
  for (int i=0; i<120; i++) herbivores.add(new Herbivore(random(width), random(height))); 
  for (int i=0; i<12;  i++) predators.add(new Predator(random(width), random(height)));

  // sliders (values are per second)
  sFood     = new Slider(uiMargin, height - hudH - 3*(28) - 10, min(360, width - uiMargin*2), 16, 0, 8, 1.2, "Auto Food Rate", "dep/s");
  sHerbRate = new Slider(uiMargin, height - hudH - 2*(28) - 6,  min(360, width - uiMargin*2), 16, 0, 5, 0.5, "Herbivore Spawn", "/s");
  sPredRate = new Slider(uiMargin, height - hudH - (28) - 2,   min(360, width - uiMargin*2), 16, 0, 3, 0.15, "Predator Spawn", "/s");

  lastMillis = millis();
}

void buildFields(int w, int h) {
  nutrients      = new NutrientField(w, h, CELL);
  herbivoreScent = new ScentField(w, h, CELL);
  flow           = new FlowField(w, h, CELL);
}

void draw() {
  // dt
  int now = millis();
  float dt = (now - lastMillis) / 1000.0f;
  if (dt < 0) dt = 0;
  lastMillis = now;

  // background trails
  noStroke();
  fill(0, 0, 0, BG_FADE);
  rect(0, 0, width, height);

  // fields
  nutrients.step();
  herbivoreScent.decayAndDiffuse();
  if (animateFlow) flow.update();

  // auto generators via Poisson-like accumulators
  if (sFood.value > 0) {
    accFood += sFood.value * dt;
    while (accFood >= 1.0) {
      autoDepositFood();
      accFood -= 1.0;
    }
  }
  if (sHerbRate.value > 0) {
    accHerb += sHerbRate.value * dt;
    while (accHerb >= 1.0) {
      spawnHerbivoreRandomEdge();
      accHerb -= 1.0;
    }
  }
  if (sPredRate.value > 0) {
    accPred += sPredRate.value * dt;
    while (accPred >= 1.0) {
      spawnPredatorRandomEdge();
      accPred -= 1.0;
    }
  }

  // herbivores
  for (Herbivore h : herbivores) {
    h.behave();
    h.update();
    h.wrap();
    h.display();
    herbivoreScent.stamp(h.pos.x, h.pos.y, 0.7);
    float eat = nutrients.consume(h.pos.x, h.pos.y, 0.25, CELL*1.6);
    h.energy = constrain(h.energy + eat*0.9, 0, 1.6);
    h.onEat(eat); // <-- track intake toward split
  }

  // predators
  ArrayList<Herbivore> eaten = new ArrayList<Herbivore>();
  for (Predator p : predators) {
    p.behave();
    Herbivore target = nearestHerbivore(p.pos, CELL*2.2);
    if (target != null && PVector.dist(target.pos, p.pos) < CELL*1.0) {
      eaten.add(target);
      p.energy = min(p.energy + 0.35, 2.0);
      p.onKill(); // <-- track kills toward split
    }
    p.update();
    p.wrap();
    p.display();
  }
  herbivores.removeAll(eaten);

  reproduceAndCull(); // now split-driven

  // ripples
  for (int i=ripples.size()-1; i>=0; i--) {
    Ripple r = ripples.get(i);
    r.update();
    r.draw();
    if (r.done()) ripples.remove(i);
  }

  if (showFields) {
    nutrients.drawOverlay();
    herbivoreScent.drawOverlay();
    flow.drawOverlay();
  }

  // UI
  layoutUI(); // keeps sliders anchored after resize / fullscreen
  sFood.draw();
  sHerbRate.draw();
  sPredRate.draw();

  drawHUD();
}

/* --------------------------- Input -------------------------------------- */

void mousePressed() {
  // give sliders first dibs
  if (sFood.mousePressed() || sHerbRate.mousePressed() || sPredRate.mousePressed()) return;

  boolean shock = (mouseButton == RIGHT) || (keyPressed && (keyCode == SHIFT));
  if (!shock) {
    nutrients.deposit(mouseX, mouseY, 12.0, 70);
    ripples.add(new Ripple(mouseX, mouseY, 120, color(110, 70, 90, 60)));
  } else {
    repelShockwave(mouseX, mouseY, 160, 2.4);
    ripples.add(new Ripple(mouseX, mouseY, 200, color(20, 80, 100, 65)));
  }
}

void mouseDragged() {
  if (sFood.mouseDragged() || sHerbRate.mouseDragged() || sPredRate.mouseDragged()) return;

  boolean shock = (mouseButton == RIGHT) || (keyPressed && (keyCode == SHIFT));
  if (!shock) {
    nutrients.deposit(mouseX, mouseY, 4.2, 48);
    ripples.add(new Ripple(mouseX, mouseY, 90, color(110, 70, 90, 40)));
  } else {
    repelShockwave(mouseX, mouseY, 160, 1.8);
    ripples.add(new Ripple(mouseX, mouseY, 200, color(20, 80, 100, 45)));
  }
}

void mouseReleased() {
  sFood.mouseReleased();
  sHerbRate.mouseReleased();
  sPredRate.mouseReleased();
}

void keyPressed() {
  if (key == 'g' || key == 'G') showFields = !showFields;
  if (key == 'f' || key == 'F') animateFlow = !animateFlow;
  if (key == 'x' || key == 'X') toggleFullscreen();
  if (key == 'e' || key == 'E') evolutionOn = !evolutionOn;
  if (key == '1') for (int i=0; i<25; i++) herbivores.add(new Herbivore(mouseX+random(-20,20), mouseY+random(-20,20)));
  if (key == '2') for (int i=0; i<5;  i++) predators.add(new Predator(mouseX+random(-20,20), mouseY+random(-20,20)));
  if (key == 'c' || key == 'C') {
    herbivores.clear();
    predators.clear();
    nutrients.clear();
    herbivoreScent.clear();
    ripples.clear();
  }
}

void toggleFullscreen() {
  // record old size BEFORE changing
  int oldW = width, oldH = height;

  if (!isFullscreen) {
    winW = oldW; winH = oldH; // remember windowed size
    surface.setLocation(0, 0);
    surface.setSize(displayWidth, displayHeight);
    isFullscreen = true;
    onResize(oldW, oldH, displayWidth, displayHeight);
  } else {
    surface.setSize(winW, winH);
    isFullscreen = false;
    onResize(oldW, oldH, winW, winH);
  }
}

void onResize(int oldW, int oldH, int newW, int newH) {
  // scale agents to new window size
  float sx = newW / max(1.0f*oldW, 1.0f);
  float sy = newH / max(1.0f*oldH, 1.0f);
  for (Herbivore h : herbivores) { h.pos.x *= sx; h.pos.y *= sy; }
  for (Predator  p : predators)  { p.pos.x *= sx; p.pos.y *= sy; }

  // rebuild fields to match new size; overlays/grid adapt automatically
  buildFields(newW, newH);

  // re-layout sliders next frame in layoutUI()
}

/* ----------------------------- Agents ---------------------------------- */

abstract class Agent {
  PVector pos = new PVector();
  PVector vel = new PVector();
  PVector acc = new PVector();
  float maxSpeed, maxForce;
  float energy = 1.0;
  float body = 6;

  Agent(float x, float y) {
    pos.set(x, y);
    vel = PVector.random2D().mult(random(0.5, 2.0));
  }

  void applyForce(PVector f) { acc.add(f); }

  void update() {
    vel.add(acc);
    vel.limit(maxSpeed);
    pos.add(vel);
    acc.mult(0);
    energy -= 0.0009 * (maxSpeed + maxForce*6.0);
    if (energy < 0) energy = 0;
  }

  void wrap() {
    if (pos.x < 0) pos.x += width;
    if (pos.y < 0) pos.y += height;
    if (pos.x >= width)  pos.x -= width;
    if (pos.y >= height) pos.y -= height;
  }

  void display() {
    float heading = atan2(vel.y, vel.x);
    pushMatrix();
    translate(pos.x, pos.y);
    rotate(heading);
    noStroke();
    drawBody();
    popMatrix();
  }

  abstract void behave();
  abstract void drawBody();
}

class Herbivore extends Agent {
  // evolutionary bookkeeping
  float intake = 0;   // nutrients since last split
  int   generation = 0;

  // behavior weights (subject to mutation)
  float gradW = 1.2f, flowW = 0.8f, avoidW = 1.6f;

  Herbivore(float x, float y) {
    super(x, y);
    maxSpeed = 3.0;
    maxForce = 0.18;
    body = 6.5;
    // small diversity at birth
    maxSpeed = clamp(mutateAround(maxSpeed, 0.05), 2.2, 4.2);
    maxForce = clamp(mutateAround(maxForce, 0.05), 0.12, 0.28);
    gradW    = clamp(mutateAround(gradW,    0.10), 0.6,  2.0);
    flowW    = clamp(mutateAround(flowW,    0.10), 0.3,  1.6);
    avoidW   = clamp(mutateAround(avoidW,   0.10), 0.6,  3.0);
  }

  void onEat(float a) { intake += a; }

  boolean readyToSplit() {
    return evolutionOn && herbivores.size() < MAX_HERB && intake >= HERB_GOAL_INTAKE && energy > 0.8;
  }

  ArrayList<Herbivore> splitOffspring() {
    ArrayList<Herbivore> kids = new ArrayList<Herbivore>();
    int children = 4;
    float share = energy / (children + 0.001f);
    for (int i=0; i<children; i++) {
      Herbivore b = new Herbivore(pos.x + random(-6,6), pos.y + random(-6,6));
      // inherit & mutate traits
      b.maxSpeed = clamp(mutateAround(this.maxSpeed, 0.15), 2.0, 4.5);
      b.maxForce = clamp(mutateAround(this.maxForce, 0.20), 0.10, 0.30);
      b.gradW    = clamp(mutateAround(this.gradW,    0.20), 0.5,  2.5);
      b.flowW    = clamp(mutateAround(this.flowW,    0.20), 0.2,  2.0);
      b.avoidW   = clamp(mutateAround(this.avoidW,   0.20), 0.5,  3.5);
      b.body     = clamp(mutateAround(this.body,     0.10), 5.4,  8.6);
      b.generation = this.generation + 1;
      b.energy = min(1.2, share * 0.95);
      b.vel = this.vel.copy().rotate(random(-0.35, 0.35));
      kids.add(b);
    }
    return kids;
  }

  void behave() {
    PVector g = nutrients.gradient(pos.x, pos.y, 1.0);
    PVector gradSteer = new PVector();
    if (g.magSq() > 1e-6) {
      PVector desired = g.copy().normalize().setMag(maxSpeed*0.95);
      gradSteer = PVector.sub(desired, vel).limit(maxForce*1.4);
    }

    PVector flowDir = flow.lookup(pos.x, pos.y);
    PVector flowDesired = flowDir.copy().setMag(maxSpeed*0.6);
    PVector flowSteer = PVector.sub(flowDesired, vel).limit(maxForce*0.7);

    PVector avoid = avoidPredators(pos, CELL*3.6);

    applyForce(gradSteer.mult(gradW));
    applyForce(flowSteer.mult(flowW));
    applyForce(avoid.mult(avoidW));
  }

  void drawBody() {
    float hue = map(energy, 0, 1.6, 70, 120);
    fill(hue, 80, 100, 85);
    triangle(-body*0.9, -body*0.55, -body*0.9, body*0.55, body*1.2, 0);
    fill(hue, 80, 40, 70);
    ellipse(-body*0.8, 0, body*0.7, body*0.7);
  }
}

class Predator extends Agent {
  int kills = 0;
  int generation = 0;

  // behavior weights (subject to mutation)
  float chaseW = 1.0f, scentW = 1.0f, flowW = 1.0f;

  Predator(float x, float y) {
    super(x, y);
    maxSpeed = 3.8;
    maxForce = 0.22;
    body = 9.5;
    // small diversity at birth
    maxSpeed = clamp(mutateAround(maxSpeed, 0.05), 3.0, 5.0);
    maxForce = clamp(mutateAround(maxForce, 0.05), 0.15, 0.30);
    chaseW   = clamp(mutateAround(chaseW,   0.10), 0.6,  2.0);
    scentW   = clamp(mutateAround(scentW,   0.10), 0.6,  2.0);
