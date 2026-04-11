#include <Adafruit_NeoPixel.h>

#define GRID_ID "DEVICE:GRID_AI - HOME"
#define FIRMWARE_VERSION "VERSION:0.1.0"
#define SENSORS "SENSORS:14"
#define BAUD_RATE 115200

#define MAX_BUFFER 200
char buffer[MAX_BUFFER];

void setup() {
    // Na Bluno Mega, Serial(0) é compartilhada com o Bluetooth
    Serial.begin(BAUD_RATE);
}

void handshake_check() {
    Serial.println(GRID_ID);
    Serial.println(SENSORS);
    Serial.println(FIRMWARE_VERSION);
    Serial.println("READY");
}

void loop() {
    if (Serial.available()) {
        // Lê a entrada até o caractere de nova linha
        int len = Serial.readBytesUntil('\n', buffer, MAX_BUFFER - 1);

        if (len > 0) {
            buffer[len] = '\0';

            // Remove caracteres de escape como '\r' que podem vir do Flutter ou terminais
            char *ptr = strchr(buffer, '\r');
            if (ptr) *ptr = '\0';

            // Compara apenas a string limpa
            if (strcmp(buffer, "HANDSHAKE") == 0) {
                handshake_check();
            }
        }
    }
}