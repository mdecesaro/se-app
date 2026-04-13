#include <Adafruit_NeoPixel.h>
#include <EEPROM.h>

#define GRID_ID "DEVICE:GRID_AI - HOME"
#define FIRMWARE_VERSION "VERSION:1.0.0"
#define SENSORS "SENSORS:14"

#define BAUD_RATE 115200


// ====== CONFIG ======

const int MAX_SEQUENCES  = 8;
const int MAX_BUFFER     = 256;
const int EEPROM_ADDR    = 0;
const int TOTAL_LEDS     = 3;
const int RANDOM_SEED    = 14;
const int SENSOR_COUNT   = 14;

// Pins
int sensor_pins[ SENSOR_COUNT ] = {
  A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13
};

// Adafruit_NeoPixel per sensor
Adafruit_NeoPixel pixels[SENSOR_COUNT] = {
  Adafruit_NeoPixel(TOTAL_LEDS, 22, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 24, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 26, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 28, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 30, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 32, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 34, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 36, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 38, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 40, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 42, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 44, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 46, NEO_GRB + NEO_KHZ800),
  Adafruit_NeoPixel(TOTAL_LEDS, 48, NEO_GRB + NEO_KHZ800)
};

// ====== DYNAMIC SEQUENCES ======
int sequences[MAX_SEQUENCES][SENSOR_COUNT];
int delays[MAX_SEQUENCES][SENSOR_COUNT];  // If Delay Range

int seq_len = 0;
int execution_rounds = 0;

// results
const int MAX_EVENTS = 1024;
unsigned long reaction_log[ MAX_SEQUENCES * SENSOR_COUNT * 2 ];
int reaction_log_idx = 0;

// Protocolo otimizado
#define MAX_BUFFER 200
char buffer[MAX_BUFFER];
unsigned long correct_color;

// ====== STATE ARRAYS (per-sensor) ======

bool parseProtocol(char *buf) {
  char local[MAX_BUFFER];
  strncpy(local, buf, MAX_BUFFER);
  local[MAX_BUFFER-1] = '\0';

  char *t = strtok(local, "|");
  if (!t) return;

  // 1) SC — sequence length
  int stimuli_count = atoi(t);
  seq_len = stimuli_count;

  // 2) SEQ — random or manual
  t = strtok(NULL, "|");
  bool manual = false;
  if (t && strcmp(t, "0") != 0)
    manual = true;

  // 3) DELAY fixed or range
  t = strtok(NULL, "|");
  char d_range[20];
  strncpy(d_range, t, sizeof(d_range));
  d_range[sizeof(d_range) - 1] = '\0';

  // 4) ROUNDS
  t = strtok(NULL, "|");
  execution_rounds = t ? atoi(t) : 1;

  // 5) COLORHEX → converter para 32 bits
  t = strtok(NULL, "|");
  correct_color = strtoul(t, NULL, 16);

  parseRange(d_range);
  if (manual) {
    //parseSequenceManual(0, strtok(NULL, "|"));
  } else {
    for (int s = 0; s < execution_rounds; s++) {
      generateOneRandomSequence(s, seq_len);
    }
  }
  return true;
}

void parseRange(char* d_range){
    int fixed = 0;
    int minVal = 0;
    int maxVal = 0;

    if(d_range && strchr(d_range, ',') == NULL) {
      fixed = atoi(d_range);

      Serial.print("Fixed: ");
      Serial.println(fixed);
    } else {
      char* p = strtok(d_range, ",");
      minVal = atoi(p);
      p = strtok(NULL, ",");
      maxVal = atoi(p);

      Serial.print("Range: ");
      Serial.print(minVal);
      Serial.print("-");
      Serial.println(maxVal);
    }

    for (int i = 0; i < execution_rounds; i++) {
        for (int j = 0; j < SENSOR_COUNT; j++) {
          if(fixed != 0) {
            delays[i][j] = fixed;
          } else {
            delays[i][j] = random(minVal, maxVal + 1);
          }
        }
    }
}


// ===== Fisher–Yates shuffle helper =====
void shuffleArray(int *arr, int n) {
  for (int i = n - 1; i > 0; i--) {
    int j = random(0, i + 1);
    int t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
}

// ===== Generate one random sequence of length 'len' using sensors 0..(sensor_count_active-1) =====
void generateOneRandomSequence(int seqIndex, int len) {
  int pool[SENSOR_COUNT];
  for (int i = 0; i < SENSOR_COUNT; i++) {
    pool[i] = i;
  }
  int out = 0;
  while (out < len) {
    shuffleArray(pool, SENSOR_COUNT);
    for (int k = 0; k < SENSOR_COUNT && out < len; k++) {
      sequences[seqIndex][out++] = pool[k];
    }
  }
}

void memset_exec_arrays() {
  memset(sequences, 0, sizeof(sequences));
  memset(delays, 0, sizeof(delays));
}

void print_sequence() {
  for (int seqIndex = 0; seqIndex < execution_rounds; seqIndex++) {
      Serial.print("Sequence ");
      Serial.print(seqIndex);
      Serial.print(": ");
      for (int pos = 0; pos < seq_len; pos++) {
        Serial.print(sequences[seqIndex][pos]);
        if (pos < seq_len - 1)
          Serial.print(","); // separador
      }
      Serial.println();
  }
}

// ===== Wait for press on target sensor and returns reaction ms =====
unsigned long waitForPressOnTarget(int targetIdx) {
  unsigned long start = millis();

  while (true) {
    int reading = analogRead(sensor_pins[targetIdx]);
    if(reading > 30){
      unsigned long reaction = millis() - start;
      return reaction;
    }
    // optional: handle timeout here (if desired, break and return large value)
    delay(1);
  }
}

// ===== Main run exercise =====
void runExercise() {
  unsigned long totalStart = millis();

  int hits = 0;
  int misses = 0;
  reaction_log_idx = 0;

  for (int r = 0; r < execution_rounds; r++) {
    for (int pos = 0; pos < seq_len; pos++) {
      int sensorIdx = sequences[r][pos];

      // Delay between execution
      delay(delays[r][pos]);

      // Activate Sensor
      activateSensorLED(0);
      sendEvent_ON(r+1, sensorIdx+1);

      // Waiting Sensor
      unsigned long rt = waitForPressOnTarget(0);

      // Deactivate Sensor
      deactivateSensorLED(0);
      reaction_log[reaction_log_idx++] = rt;
      sendEvent_HIT(r+1, sensorIdx+1, rt, delays[r][pos]);
      hits++;

    }
  }

  unsigned long totalMs = millis() - totalStart;
  memset_exec_arrays();
  sendEvent_END(totalMs, hits, misses);
  sendEvent_DONE();

}

// ===== Events to PC =====

// EVT|ON|1|1
void sendEvent_ON(int round, int sensorIdx) {
  Serial.print("EVT|ON|");
  Serial.print(round);
  Serial.print("|");
  Serial.println(sensorIdx);
}

// EVT|HIT|1|1|510|700
void sendEvent_HIT(int round, int sensorIdx, unsigned long ms, int delay) {
  Serial.print("EVT|HIT|");
  Serial.print(round);
  Serial.print("|");
  Serial.print(sensorIdx);
  Serial.print("|");
  Serial.print(ms);
  Serial.print("|");
  Serial.println(delay);
}

void sendEvent_END(unsigned long total_ms, int hits, int misses) {
  Serial.print("EVT|END|");
  Serial.print(total_ms);
  Serial.print("|");
  Serial.print(hits);
  Serial.print("|");
  Serial.println(misses);
}
void sendEvent_DONE() {
  Serial.println("DONE");
}

// ===== Activate / Deactivate NeoPixel(s) for sensor index =====
uint32_t colorFromHex(unsigned long hexValue) {
  byte r = (hexValue >> 16) & 0xFF;
  byte g = (hexValue >> 8) & 0xFF;
  byte b = hexValue & 0xFF;
  return pixels[0].Color(r, g, b);
}

void activateSensorLED(int idx) {
  for (int j = 0; j < TOTAL_LEDS; j++) {
    pixels[idx].setPixelColor(j, colorFromHex(correct_color));
  }
  pixels[idx].show();
}

void deactivateSensorLED(int idx) {
  pixels[idx].clear();
  pixels[idx].show();
}

void handshake_check() {
  Serial.println(GRID_ID);
  Serial.println(SENSORS);
  Serial.println(FIRMWARE_VERSION);
  Serial.println("READY");
}

// ===== SETUP =====
void setup() {
  Serial.begin(BAUD_RATE);

  for(int i=0;i<SENSOR_COUNT;i++){
    pixels[i].begin();
    pixels[i].clear();
    pixels[i].show();
  }
  randomSeed(analogRead(RANDOM_SEED) ^ micros());
}

// ===== LOOP =====
bool protocol_ready = false;
void loop() {
  if (Serial.available()) {
    int len = Serial.readBytesUntil('\n', buffer, MAX_BUFFER);
    buffer[len] = '\0';
    buffer[strcspn(buffer, "\r")] = 0;

    if (strcmp(buffer, "HANDSHAKE") == 0) {
        handshake_check();
    }
    else if (strncmp(buffer, "SET|", 4) == 0) {
      if (parseProtocol(buffer + 4)) {
        protocol_ready = true;
        Serial.println("SET_OK");
      } else {
        protocol_ready = false;
        Serial.println("SET_ERROR");
      }
    }
    else if (strcmp(buffer, "START") == 0) {
      if (!protocol_ready) {
        Serial.println("ERROR|NO_SET");
        return;
      }

      Serial.println("START_OK");
      runExercise();

      protocol_ready = false;
    }
  }
}