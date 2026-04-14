#include <Adafruit_NeoPixel.h>

#define GRID_ID "DEVICE:GRID_AI - HOME"
#define FIRMWARE_VERSION "VERSION:1.1.0"
#define SENSORS "SENSORS:14"
#define BAUD_RATE 115200

// ====== CONFIG ======
const int MAX_ROUNDS      = 8;
const int MAX_STIMULI     = 50;
const int MAX_BUFFER      = 512;
const int TOTAL_LEDS      = 3;
const int SENSOR_COUNT    = 14;
const int MAX_DISTRACTORS = 5;

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

// Protocol Variables
int sequences[MAX_ROUNDS][MAX_STIMULI];
int delays_array[MAX_ROUNDS][MAX_STIMULI];
int seq_len = 0;
int execution_rounds = 0;
unsigned long correct_color = 0xFFFFFF;
int distractor_count = 0;
uint32_t distractor_colors[MAX_DISTRACTORS];
int timeout_ms = 0;
bool repeat_if_wrong = false;
char buffer[MAX_BUFFER];

void generateOneRandomSequence(int roundIdx, int len) {
    for (int i = 0; i < len; i++) sequences[roundIdx][i] = random(0, SENSOR_COUNT);
}

void parseRangeSafe(char* d_range) {
    int minVal = 0, maxVal = 0, fixed = 0;
    char* comma = strchr(d_range, ',');
    if (comma) { *comma = '\0'; minVal = atoi(d_range); maxVal = atoi(comma + 1); }
    else { fixed = atoi(d_range); }
    for (int r = 0; r < MAX_ROUNDS; r++) {
        for (int j = 0; j < MAX_STIMULI; j++) delays_array[r][j] = (fixed != 0) ? fixed : random(minVal, maxVal + 1);
    }
}

void parseDistColors(char* colors_str) {
    char* start = colors_str;
    int i = 0;
    while (start && i < MAX_DISTRACTORS) {
        char* comma = strchr(start, ',');
        if (comma) *comma = '\0';
        distractor_colors[i++] = strtoul(start, NULL, 16);
        if (comma) start = comma + 1; else break;
    }
}

void parseSequenceSafe(char* seq_str) {
    char* start = seq_str;
    int i = 0;
    while (start && i < seq_len && i < MAX_STIMULI) {
        char* comma = strchr(start, ',');
        if (comma) *comma = '\0';
        int sensorId = atoi(start);
        for (int r = 0; r < MAX_ROUNDS; r++) sequences[r][i] = sensorId - 1;
        if (comma) start = comma + 1; else break;
        i++;
    }
}

bool parseProtocol(char *buf) {
    // SET|count|manual|delay|rounds|color|stim_type|dist_type|dist_count|dist_colors|timeout|repeat|seq
    char *t = strtok(buf, "|"); if (!t) return false;
    seq_len = atoi(t);

    t = strtok(NULL, "|"); bool manual = (t && atoi(t) == 1);
    t = strtok(NULL, "|"); char d_range[32]; if (t) strncpy(d_range, t, 31);
    t = strtok(NULL, "|"); execution_rounds = t ? atoi(t) : 1;
    t = strtok(NULL, "|"); if (t) correct_color = strtoul(t, NULL, 16);

    t = strtok(NULL, "|"); // stimulus_type (ignored for now)
    t = strtok(NULL, "|"); // distractor_type (ignored for now)

    t = strtok(NULL, "|"); distractor_count = t ? atoi(t) : 0;
    t = strtok(NULL, "|"); if (t) parseDistColors(t);

    t = strtok(NULL, "|"); timeout_ms = t ? atoi(t) : 0;
    t = strtok(NULL, "|"); repeat_if_wrong = (t && atoi(t) == 1);

    parseRangeSafe(d_range);
    if (!manual) {
        for (int r = 0; r < execution_rounds; r++) generateOneRandomSequence(r, seq_len);
    } else {
        t = strtok(NULL, "|"); if (t) parseSequenceSafe(t);
    }
    return true;
}

void activateLED(int idx, uint32_t color) {
    if (idx < 0 || idx >= SENSOR_COUNT) return;
    for (int j = 0; j < TOTAL_LEDS; j++) pixels[idx].setPixelColor(j, color);
    pixels[idx].show();
}

void clearLED(int idx) { if (idx >= 0 && idx < SENSOR_COUNT) { pixels[idx].clear(); pixels[idx].show(); } }

void showDistractors(int targetIdx) {
    int shown = 0;
    int attempts = 0;
    while (shown < distractor_count && attempts < 30) {
        int rnd = random(0, SENSOR_COUNT);
        if (rnd != targetIdx) {
            activateLED(rnd, distractor_colors[shown % MAX_DISTRACTORS]);
            shown++;
        }
        attempts++;
    }
}

void clearAllLEDs() { for (int i = 0; i < SENSOR_COUNT; i++) { pixels[i].clear(); pixels[i].show(); } }

unsigned long waitForPress(int targetIdx) {
    unsigned long start = millis();
    while (true) {
        if (analogRead(sensor_pins[targetIdx]) > 50) return millis() - start;

        // Check for wrong presses
        for (int i = 0; i < SENSOR_COUNT; i++) {
            if (i != targetIdx && analogRead(sensor_pins[i]) > 50) return 0xFFFFFFFF; // Error code
        }

        if (timeout_ms > 0 && (millis() - start) > (unsigned long)timeout_ms) return 0; // Timeout

        if (Serial.available()) {
            String cmd = Serial.readStringUntil('\n');
            if (cmd.indexOf("STOP") != -1) return 0;
        }
        delay(1);
    }
}

void runExercise() {
    unsigned long totalStart = millis();
    int total_hits = 0;
    int total_misses = 0;

    for (int r = 0; r < execution_rounds; r++) {
        for (int pos = 0; pos < seq_len; pos++) {
            int sensorIdx = sequences[r][pos];
            bool resolved = false;

            while (!resolved) {
                delay(delays_array[r][pos]);

                //clearAllLEDs();
                //activateLED(sensorIdx, pixels[0].Color((correct_color >> 16) & 0xFF, (correct_color >> 8) & 0xFF, correct_color & 0xFF));
                //showDistractors(sensorIdx);

                Serial.print("EVT|ON|");
                Serial.print(r + 1);
                Serial.print("|");
                Serial.println(sensorIdx + 1);

                unsigned long rt = 535;
                delay(538);//waitForPress(sensorIdx);

                clearAllLEDs();
                if (rt == 0 || rt == 0xFFFFFFFF) { // Timeout or Wrong
                    total_misses++;
                    Serial.print("EVT|MISS|"); Serial.print(r + 1); Serial.print("|"); Serial.print(sensorIdx + 1);
                    Serial.print("|"); Serial.print(rt == 0 ? "TIMEOUT" : "ERROR"); Serial.print("|"); Serial.println(delays_array[r][pos]);
                    if (!repeat_if_wrong) resolved = true;
                } else {
                    total_hits++;
                    Serial.print("EVT|HIT|"); Serial.print(r + 1); Serial.print("|"); Serial.print(sensorIdx + 1);
                    Serial.print("|"); Serial.print(rt); Serial.print("|"); Serial.println(delays_array[r][pos]);
                    resolved = true;
                }
            }
        }
    }
    Serial.print("EVT|END|"); Serial.print(millis() - totalStart); Serial.print("|"); Serial.print(total_hits); Serial.print("|"); Serial.println(total_misses);
    Serial.println("DONE");
}

void setup() {
    Serial.begin(BAUD_RATE);
    for (int i = 0; i < SENSOR_COUNT; i++) { pixels[i].begin(); pixels[i].clear(); pixels[i].show(); }
    randomSeed(analogRead(0) + micros());
}

bool protocol_ready = false;
void loop() {
    if (Serial.available()) {
        int len = Serial.readBytesUntil('\n', buffer, MAX_BUFFER - 1);
        if (len > 0) {
            buffer[len] = '\0';
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
