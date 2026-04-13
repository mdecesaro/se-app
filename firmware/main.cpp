#include <Adafruit_NeoPixel.h>

#define GRID_ID "DEVICE:GRID_AI - HOME"
#define FIRMWARE_VERSION "VERSION:1.0.0"
#define SENSORS "SENSORS:14"
#define BAUD_RATE 115200

// ====== CONFIG ======
const int MAX_ROUNDS     = 8;
const int MAX_STIMULI    = 50;
const int MAX_BUFFER     = 256;
const int TOTAL_LEDS     = 3;
const int RANDOM_SEED_PIN = 14;
const int SENSOR_COUNT   = 14;

int sensor_pins[SENSOR_COUNT] = { A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13 };

Adafruit_NeoPixel pixels[SENSOR_COUNT] = {
  Adafruit_NeoPixel(TOTAL_LEDS, 22, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 24, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 26, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 28, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 30, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 32, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 34, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 36, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 38, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 40, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 42, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 44, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 46, NEO_GRB + NEO_KHZ800), Adafruit_NeoPixel(TOTAL_LEDS, 48, NEO_GRB + NEO_KHZ800)
};

int sequences[MAX_ROUNDS][MAX_STIMULI];
int delays_array[MAX_ROUNDS][MAX_STIMULI];
int seq_len = 0;
int execution_rounds = 0;
char buffer[MAX_BUFFER];
unsigned long correct_color = 0xFFFFFF;

void shuffleArray(int *arr, int n) {
  for (int i = n - 1; i > 0; i--) {
    int j = random(0, i + 1);
    int t = arr[i]; arr[i] = arr[j]; arr[j] = t;
  }
}

void generateOneRandomSequence(int roundIdx, int len) {
  int pool[SENSOR_COUNT];
  for (int i = 0; i < SENSOR_COUNT; i++) pool[i] = i;
  int out = 0;
  while (out < len) {
    shuffleArray(pool, SENSOR_COUNT);
    for (int k = 0; k < SENSOR_COUNT && out < len; k++) {
      sequences[roundIdx][out++] = pool[k];
    }
  }
}

// SAFE parseRange using manual pointer instead of strtok (which conflicts with parseProtocol)
void parseRangeSafe(char* d_range) {
  int minVal = 0, maxVal = 0, fixed = 0;
  char* comma = strchr(d_range, ',');
  if (comma) {
    *comma = '\0';
    minVal = atoi(d_range);
    maxVal = atoi(comma + 1);
  } else {
    fixed = atoi(d_range);
  }
  for (int r = 0; r < MAX_ROUNDS; r++) {
    for (int j = 0; j < MAX_STIMULI; j++) {
      delays_array[r][j] = (fixed != 0) ? fixed : random(minVal, maxVal + 1);
    }
  }
}

bool parseProtocol(char *buf) {
  char *t = strtok(buf, "|");
  if (!t) return false;
  seq_len = atoi(t);

  t = strtok(NULL, "|");
  bool manual = (t && strcmp(t, "0") != 0);

  t = strtok(NULL, "|");
  char d_range[20];
  if (t) strncpy(d_range, t, 19);
  d_range[19] = '\0';

  t = strtok(NULL, "|");
  execution_rounds = t ? atoi(t) : 1;

  t = strtok(NULL, "|");
  if (t) correct_color = strtoul(t, NULL, 16);

  parseRangeSafe(d_range);
  if (!manual) {
    for (int r = 0; r < execution_rounds; r++) generateOneRandomSequence(r, seq_len);
  }
  return true;
}

void activateSensorLED(int idx) {
  if (idx < 0 || idx >= SENSOR_COUNT) return;
  uint32_t color = pixels[idx].Color((correct_color >> 16) & 0xFF, (correct_color >> 8) & 0xFF, correct_color & 0xFF);
  for (int j = 0; j < TOTAL_LEDS; j++) pixels[idx].setPixelColor(j, color);
  pixels[idx].show();
}

void deactivateSensorLED(int idx) {
  if (idx < 0 || idx >= SENSOR_COUNT) return;
  pixels[idx].clear(); pixels[idx].show();
}

unsigned long waitForPressOnTarget(int targetIdx) {
  unsigned long start = millis();
  while (true) {
    if (analogRead(sensor_pins[targetIdx]) > 40) return millis() - start;
    if (Serial.available()) {
      String cmd = Serial.readStringUntil('\n');
      if (cmd.indexOf("STOP") != -1) return 0;
    }
    delay(1);
  }
}

void runExercise() {
  unsigned long totalStart = millis();
  int hits = 0;
  for (int r = 0; r < execution_rounds; r++) {
    for (int pos = 0; pos < seq_len; pos++) {
      int sensorIdx = sequences[r][pos];
      delay(delays_array[r][pos]);
      activateSensorLED(sensorIdx);
      Serial.print("EVT|ON|"); Serial.print(r + 1); Serial.print("|"); Serial.println(sensorIdx + 1);
      unsigned long rt = waitForPressOnTarget(sensorIdx);
      deactivateSensorLED(sensorIdx);
      if (rt == 0) return;
      Serial.print("EVT|HIT|"); Serial.print(r + 1); Serial.print("|"); Serial.print(sensorIdx + 1);
      Serial.print("|"); Serial.print(rt); Serial.print("|"); Serial.println(delays_array[r][pos]);
      hits++;
    }
  }
  unsigned long totalMs = millis() - totalStart;
  Serial.print("EVT|END|"); Serial.print(totalMs); Serial.print("|"); Serial.print(hits); Serial.println("|0");
  Serial.println("DONE");
}

void setup() {
  Serial.begin(BAUD_RATE);
  for (int i = 0; i < SENSOR_COUNT; i++) {
    pixels[i].begin(); pixels[i].clear(); pixels[i].show();
  }
  randomSeed(analogRead(0) + micros());
}

bool protocol_ready = false;
void loop() {
  if (Serial.available()) {
    int len = Serial.readBytesUntil('\n', buffer, MAX_BUFFER - 1);
    if (len > 0) {
      buffer[len] = '\0';
      char *ptr = strchr(buffer, '\r'); if (ptr) *ptr = '\0';

      if (strcmp(buffer, "HANDSHAKE") == 0) {
        Serial.println(GRID_ID);
        delay(50);
        Serial.println(SENSORS);
        delay(50);
        Serial.println(FIRMWARE_VERSION);
        delay(50);
        Serial.println("READY");
      } else if (strncmp(buffer, "SET|", 4) == 0) {
        if (parseProtocol(buffer + 4)) {
          protocol_ready = true;
          Serial.println("SET_OK");
        } else Serial.println("SET_ERROR");
      } else if (strcmp(buffer, "START") == 0) {
        if (protocol_ready) {
          Serial.println("START_OK");
          runExercise();
          protocol_ready = false;
        } else Serial.println("ERROR|NO_SET");
      }
    }
  }
}
