import processing.event.MouseEvent;
import java.util.HashMap;
import java.util.ArrayList;

// Simple object to store one city and its values for each census year
class City {
  String name;
  int pop1991, pop2001, pop2011;
  float lat, lon;
  float x, y;

  City(String name, int pop1991, int pop2001, int pop2011, float lat, float lon) {
    this.name = name;
    this.pop1991 = pop1991;
    this.pop2001 = pop2001;
    this.pop2011 = pop2011;
    this.lat = lat;
    this.lon = lon;
  }

  // Returns the population for whichever year is currently selected
  int getPopulation(int year) {
    if (year == 1991) return pop1991;
    if (year == 2001) return pop2001;
    return pop2011;
  }
}

// Main assets and data tables
PImage ukMap;
Table popTable;

// One list for city objects and one lookup table for coordinates
ArrayList<City> cities = new ArrayList<City>();
HashMap<String, float[]> coordMap = new HashMap<String, float[]>();

// Start on the latest year by default
int currentYear = 2011;

// These control how the map is moved around on screen
float panX = 0;
float panY = 0;
float zoomFactor = 1.0;

// Used while dragging the view with the mouse
boolean dragging = false;
float prevMouseX, prevMouseY;

// Used to detect a quick double-click for reset
int lastClickTime = 0;
int doubleClickGap = 300;

// Filtering settings
int filterThreshold = 0;
boolean showOnlyAboveThreshold = false;

// Size of the map plane inside the 3D scene
float mapDisplayW = 520;
float mapDisplayH = 650;

// Rough UK bounds used to convert latitude/longitude into map positions
float minLon = -8.7;
float maxLon = 2.2;
float minLat = 49.8;
float maxLat = 59.0;

// These are recalculated whenever the selected year changes
int minPop = 1;
int maxPop = 1;

// Stores whichever city the mouse is currently closest to
City hoveredCity = null;
float hoveredScreenX = 0;
float hoveredScreenY = 0;

void setup() {
  size(700, 800, P3D);
  smooth(8);

  // Load the map image first
  ukMap = loadImage("uk-map.jpg");
  if (ukMap == null) {
    println("ERROR: Could not load UK map image.");
    exit();
  }

  // Load the CSV that contains the city populations
  popTable = loadTable("uk-city-populations.csv", "header");
  if (popTable == null) {
    println("ERROR: Could not load uk-city-populations.csv.");
    exit();
  }

  // Build the coordinate lookup, load the city data, then place each city on the map
  setupCoordinates();
  loadPopulationData();
  mapAllCitiesToImage();
  updatePopulationRange();
}

void draw() {
  background(214, 228, 242);
  lights();

  drawScene();
  drawHUD();
}

void drawScene() {
  hoveredCity = null;

  pushMatrix();

  // Move the whole scene into position, then apply zoom and a fixed viewing angle
  translate(width / 2 + panX, height / 2 + panY + 40, -120);
  scale(zoomFactor);
  rotateX(radians(60));

  // Draw the UK map as a flat textured plane
  pushMatrix();
  noStroke();
  beginShape();
  texture(ukMap);
  vertex(-mapDisplayW/2, -mapDisplayH/2, 0, 0, 0);
  vertex( mapDisplayW/2, -mapDisplayH/2, 0, ukMap.width, 0);
  vertex( mapDisplayW/2,  mapDisplayH/2, 0, ukMap.width, ukMap.height);
  vertex(-mapDisplayW/2,  mapDisplayH/2, 0, 0, ukMap.height);
  endShape(CLOSE);
  popMatrix();

  // A thin border helps separate the map plane from the background
  pushMatrix();
  noFill();
  stroke(120, 140, 160);
  box(mapDisplayW, mapDisplayH, 2);
  popMatrix();

  // This helps decide which city should show the hover box
  float nearestDist = 18;

  for (City c : cities) {
    int pop = c.getPopulation(currentYear);

    // Skip small cities when the filter is active
    if (showOnlyAboveThreshold && pop < filterThreshold) {
      continue;
    }

    if (pop <= 0) continue;

    // Log scaling keeps London large without flattening everything else
    float h = map(log(pop + 1), log(minPop + 1), log(maxPop + 1), 12, 180);

    // Colour shifts from blue to red as population increases
    float t = map(pop, minPop, maxPop, 0, 1);
    t = constrain(t, 0, 1);

    int lowCol = color(70, 160, 255);
    int highCol = color(255, 90, 70);
    int barCol = lerpColor(lowCol, highCol, t);

    float sx = c.x;
    float sy = c.y;

    // Use the top of the bar as the hover point
    pushMatrix();
    translate(sx, sy, h + 5);
    float screenPX = screenX(0, 0, 0);
    float screenPY = screenY(0, 0, 0);
    popMatrix();

    float d = dist(mouseX, mouseY, screenPX, screenPY);
    boolean isHovered = d < nearestDist;

    if (isHovered) {
      nearestDist = d;
      hoveredCity = c;
      hoveredScreenX = screenPX;
      hoveredScreenY = screenPY;
    }

    // Highlight whichever city the mouse is closest to
    if (hoveredCity == c) {
      barCol = color(255, 220, 60);
    }

    // Draw the 3D population bar
    pushMatrix();
    translate(sx, sy, h / 2.0);
    fill(barCol);
    stroke(40, 80);
    box(6, 6, h);
    popMatrix();

    // Small marker at the top makes the hover target easier to notice
    pushMatrix();
    translate(sx, sy, h + 5);
    noStroke();
    fill(20);
    sphereDetail(4);
    sphere(2.3);
    popMatrix();
  }

  popMatrix();
}

void drawHUD() {
  hint(DISABLE_DEPTH_TEST);
  camera();

  // Main information panel
  fill(0, 155);
  noStroke();
  rect(10, 10, 310, 185, 12);

  fill(255);
  textSize(16);
  text("UK Population Visualisation", 20, 33);

  textSize(13);
  text("Year: " + currentYear, 20, 58);
  text("Filter threshold: " + nfc(filterThreshold), 20, 80);
  text("Filter active: " + (showOnlyAboveThreshold ? "ON" : "OFF"), 20, 102);

  text("1 / 2 / 3 = change year", 20, 126);
  text("Arrow keys or drag = pan", 20, 146);
  text("Wheel = zoom", 20, 166);
  text("Double-click / R = reset", 20, 186);

  // Keep the legend tucked into the lower-left corner
  float legendX = 25;
  float legendW = 200;
  float legendH = 78;
  float legendY = height - legendH - 25;

  fill(0, 155);
  noStroke();
  rect(legendX, legendY, legendW, legendH, 12);

  fill(255);
  textSize(14);
  text("Population Colour Scale", legendX + 15, legendY + 24);

  // Draw the colour strip manually so the gradient is easy to read
  noStroke();
  for (int i = 0; i < 160; i++) {
    float t = map(i, 0, 159, 0, 1);
    fill(lerpColor(color(70, 160, 255), color(255, 90, 70), t));
    rect(legendX + 15 + i, legendY + 36, 1, 16);
  }

  fill(255);
  textSize(12);
  text("Low", legendX + 15, legendY + 64);
  text("High", legendX + 155, legendY + 64);

  // Only show extra details when the user hovers near a city
  if (hoveredCity != null) {
    int pop = hoveredCity.getPopulation(currentYear);

    float boxX = mouseX + 14;
    float boxY = mouseY - 80;
    float boxW = 210;
    float boxH = 65;

    if (boxX + boxW > width) boxX = mouseX - boxW - 14;
    if (boxY + boxH > height) boxY = height - boxH - 10;
    if (boxY < 10) boxY = 10;

    fill(0, 130);
    rect(boxX, boxY, boxW, boxH, 8);

    fill(255);
    textSize(13);
    text(hoveredCity.name, boxX + 10, boxY + 20);
    text("Population: " + nfc(pop), boxX + 10, boxY + 40);
    text("Lat/Lon: " + nf(hoveredCity.lat, 0, 2) + ", " + nf(hoveredCity.lon, 0, 2), boxX + 10, boxY + 58);
  }

  hint(ENABLE_DEPTH_TEST);
}

void keyPressed() {
  if (key == '1') {
    currentYear = 1991;
    updatePopulationRange();
  }
  if (key == '2') {
    currentYear = 2001;
    updatePopulationRange();
  }
  if (key == '3') {
    currentYear = 2011;
    updatePopulationRange();
  }

  if (keyCode == LEFT)  panX += 20;
  if (keyCode == RIGHT) panX -= 20;
  if (keyCode == UP)    panY += 20;
  if (keyCode == DOWN)  panY -= 20;

  // F toggles the threshold filter
  if (key == 'f' || key == 'F') {
    showOnlyAboveThreshold = !showOnlyAboveThreshold;
  }

  // Use plus and minus to change the threshold in fixed steps
  if (key == '+' || key == '=') {
    filterThreshold += 50000;
  }

  if (key == '-' || key == '_') {
    filterThreshold -= 50000;
    if (filterThreshold < 0) filterThreshold = 0;
  }

  if (key == 'r' || key == 'R') {
    resetView();
  }
}

void mousePressed() {
  dragging = true;
  prevMouseX = mouseX;
  prevMouseY = mouseY;

  // A quick double-click takes the view back to its default position
  int now = millis();
  if (now - lastClickTime < doubleClickGap) {
    resetView();
  }
  lastClickTime = now;
}

void mouseDragged() {
  // Dragging shifts the map so the user can inspect different areas
  if (dragging) {
    panX += mouseX - prevMouseX;
    panY += mouseY - prevMouseY;
    prevMouseX = mouseX;
    prevMouseY = mouseY;
  }
}

void mouseReleased() {
  dragging = false;
}

void mouseWheel(MouseEvent event) {
  // Limit zoom so the map stays easy to use
  float e = event.getCount();
  zoomFactor -= e * 0.05;
  zoomFactor = constrain(zoomFactor, 0.45, 4.0);
}

void resetView() {
  panX = 0;
  panY = 0;
  zoomFactor = 1.0;
}

void updatePopulationRange() {
  minPop = Integer.MAX_VALUE;
  maxPop = Integer.MIN_VALUE;

  // Recalculate the min and max whenever the visible year changes
  for (City c : cities) {
    int p = c.getPopulation(currentYear);
    if (p > 0) {
      if (p < minPop) minPop = p;
      if (p > maxPop) maxPop = p;
    }
  }

  if (minPop <= 0 || minPop == Integer.MAX_VALUE) minPop = 1;
  if (maxPop <= 0 || maxPop == Integer.MIN_VALUE) maxPop = 1;
}

void loadPopulationData() {
  // Read each row from the CSV and match it with stored coordinates
  for (TableRow row : popTable.rows()) {
    String cityName = trim(row.getString("City"));

    int p1991 = parsePopulation(row.getString("1991"));
    int p2001 = parsePopulation(row.getString("2001"));
    int p2011 = parsePopulation(row.getString("2011"));

    if (coordMap.containsKey(cityName)) {
      float[] coords = coordMap.get(cityName);
      City c = new City(cityName, p1991, p2001, p2011, coords[0], coords[1]);
      cities.add(c);
    }
  }

  println("Loaded cities: " + cities.size());
}

int parsePopulation(String value) {
  value = trim(value);
  if (value.equals("...") || value.length() == 0) return 0;
  value = value.replace(",", "");
  return int(value);
}

void mapAllCitiesToImage() {
  // Convert latitude and longitude into positions on the map image
  for (City c : cities) {
    float px = map(c.lon, -8.7, 2.2, -mapDisplayW/2, mapDisplayW/2);
    float py = map(c.lat, 59.0, 49.8, -mapDisplayH/2, mapDisplayH/2);
    c.x = px;
    c.y = py;
  }
}

void setupCoordinates() {
  coordMap.put("London", new float[]{51.5074, -0.1278});
  coordMap.put("Birmingham", new float[]{52.4862, -1.8904});
  coordMap.put("Glasgow", new float[]{55.8642, -4.2518});
  coordMap.put("Liverpool", new float[]{53.4084, -2.9916});
  coordMap.put("Bristol", new float[]{51.4545, -2.5879});
  coordMap.put("Sheffield", new float[]{53.3811, -1.4701});
  coordMap.put("Manchester", new float[]{53.4808, -2.2426});
  coordMap.put("Leeds", new float[]{53.8008, -1.5491});
  coordMap.put("Edinburgh", new float[]{55.9533, -3.1883});
  coordMap.put("Leicester", new float[]{52.6369, -1.1398});
  coordMap.put("Bradford", new float[]{53.7950, -1.7594});
  coordMap.put("Cardiff", new float[]{51.4816, -3.1791});
  coordMap.put("Coventry", new float[]{52.4068, -1.5197});
  coordMap.put("Nottingham", new float[]{52.9548, -1.1581});
  coordMap.put("Kingston upon Hull", new float[]{53.7676, -0.3274});
  coordMap.put("Belfast", new float[]{54.5973, -5.9301});
  coordMap.put("Stoke-on-Trent", new float[]{53.0027, -2.1794});
  coordMap.put("Wolverhampton", new float[]{52.5862, -2.1287});
  coordMap.put("Plymouth", new float[]{50.3755, -4.1427});
  coordMap.put("Derby", new float[]{52.9225, -1.4746});
  coordMap.put("Southampton", new float[]{50.9097, -1.4044});
  coordMap.put("Swansea", new float[]{51.6214, -3.9436});
  coordMap.put("Portsmouth", new float[]{50.8198, -1.0880});
  coordMap.put("Newcastle upon Tyne", new float[]{54.9783, -1.6178});
  coordMap.put("Brighton", new float[]{50.8225, -0.1372});
  coordMap.put("Hull", new float[]{53.7676, -0.3274});
  coordMap.put("Reading", new float[]{51.4543, -0.9781});
  coordMap.put("Preston", new float[]{53.7632, -2.7031});
  coordMap.put("Luton", new float[]{51.8787, -0.4200});
  coordMap.put("Aberdeen", new float[]{57.1497, -2.0943});
  coordMap.put("Bournemouth", new float[]{50.7192, -1.8808});
  coordMap.put("Norwich", new float[]{52.6309, 1.2974});
  coordMap.put("Middlesbrough", new float[]{54.5742, -1.2350});
  coordMap.put("Milton Keynes", new float[]{52.0406, -0.7594});
  coordMap.put("Sunderland", new float[]{54.9069, -1.3838});
  coordMap.put("Oxford", new float[]{51.7520, -1.2577});
  coordMap.put("Cambridge", new float[]{52.2053, 0.1218});
  coordMap.put("York", new float[]{53.9600, -1.0873});
  coordMap.put("Dundee", new float[]{56.4620, -2.9707});
  coordMap.put("Exeter", new float[]{50.7184, -3.5339});
  coordMap.put("Gloucester", new float[]{51.8642, -2.2382});
  coordMap.put("Chelmsford", new float[]{51.7356, 0.4685});
  coordMap.put("Blackpool", new float[]{53.8175, -3.0357});
  coordMap.put("Ipswich", new float[]{52.0567, 1.1482});
  coordMap.put("Peterborough", new float[]{52.5695, -0.2405});
  coordMap.put("Blackburn", new float[]{53.7486, -2.4875});
  coordMap.put("Basildon", new float[]{51.5761, 0.4887});
  coordMap.put("Huddersfield", new float[]{53.6458, -1.7850});
  coordMap.put("Poole", new float[]{50.7151, -1.9872});
  coordMap.put("West Bromwich", new float[]{52.5187, -1.9945});
  coordMap.put("Telford", new float[]{52.6766, -2.4493});
  coordMap.put("Maidstone", new float[]{51.2704, 0.5227});
  coordMap.put("Bolton", new float[]{53.5769, -2.4282});
  coordMap.put("Warrington", new float[]{53.3900, -2.5969});
  coordMap.put("Slough", new float[]{51.5105, -0.5950});
  coordMap.put("Stockport", new float[]{53.4106, -2.1575});
  coordMap.put("Rotherham", new float[]{53.4326, -1.3635});
  coordMap.put("Woking", new float[]{51.3168, -0.5560});
  coordMap.put("Oldham", new float[]{53.5409, -2.1114});
  coordMap.put("Southend-on-Sea", new float[]{51.5459, 0.7077});
  coordMap.put("Watford", new float[]{51.6565, -0.3903});
  coordMap.put("Colchester", new float[]{51.8892, 0.9042});
  coordMap.put("Mansfield", new float[]{53.1435, -1.1986});
  coordMap.put("Wigan", new float[]{53.5443, -2.6318});
  coordMap.put("Doncaster", new float[]{53.5228, -1.1285});
  coordMap.put("Cheltenham", new float[]{51.8994, -2.0783});
  coordMap.put("Worthing", new float[]{50.8179, -0.3729});
  coordMap.put("Rochdale", new float[]{53.6154, -2.1552});
  coordMap.put("Gillingham", new float[]{51.3850, 0.5490});
  coordMap.put("Wycombe", new float[]{51.6290, -0.7490});
  coordMap.put("Solihull", new float[]{52.4118, -1.7776});
  coordMap.put("Barnsley", new float[]{53.5526, -1.4797});
  coordMap.put("Tynemouth", new float[]{55.0179, -1.4253});
  coordMap.put("Scarborough", new float[]{54.2798, -0.4044});
  coordMap.put("Bath", new float[]{51.3811, -2.3590});
  coordMap.put("Chesterfield", new float[]{53.2350, -1.4216});
  coordMap.put("Stevenage", new float[]{51.9038, -0.1966});
  coordMap.put("Birkenhead", new float[]{53.3925, -3.0148});
  coordMap.put("Wakefield", new float[]{53.6833, -1.4977});
  coordMap.put("Burnley", new float[]{53.7893, -2.2405});
  coordMap.put("Hastings", new float[]{50.8543, 0.5735});
  coordMap.put("Lincoln", new float[]{53.2307, -0.5406});
  coordMap.put("Harlow", new float[]{51.7729, 0.1023});
  coordMap.put("Rugby", new float[]{52.3709, -1.2642});
  coordMap.put("Londonderry", new float[]{54.9966, -7.3086});
  coordMap.put("Canterbury", new float[]{51.2802, 1.0789});
  coordMap.put("Eastbourne", new float[]{50.7680, 0.2905});
  coordMap.put("Grimsby", new float[]{53.5654, -0.0754});
  coordMap.put("Hove", new float[]{50.8352, -0.1706});
}
