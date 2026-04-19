# 🛰️ Serial Communication Protocol - V1.0.0 (Stable Release)

This document defines the communication contract between the App (Control Center) and the Firmware (Sensors).

## 1. Configuration Command (App ➔ Firmware)

The `SET` command initializes the exercise parameters.

**Format:**
`SET|stimuli_count|stimuli_rounds|stimuli_mode|stimuli_color|dist_qty|dist_colors|delay_type|delay_min|delay_max|timeout_ms|repeat_if_wrong`

### 📋 Parameter Mapping (SET)

| Index | Field | Type | Serial Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `stimuli_count` | int | `int` | Hits required per round. |
| 2 | `stimuli_rounds` | int | `int` | Total number of rounds/sets. |
| 3 | `stimuli_mode` | int | `1` or `2` | **1**: Random, **2**: Pattern. |
| 4 | `stimuli_color` | string | `hex` | Target color (e.g., 00FF00). |
| 5 | `dist_qty` | int | `int` | Qty of simultaneous distractors (0-3). |
| 6 | `dist_colors` | array | `list/0` | HEX list or `0` if none. |
| 7 | `delay_type` | int | `1` or `2` | **1**: Fixed, **2**: Range. |
| 8 | `delay_min` | int | `ms` | Minimum delay before stimulus. |
| 9 | `delay_max` | int | `ms` | Maximum delay (equal to min if fixed). |
| 10 | `timeout_ms` | int | `ms` | Time limit to hit (0 = infinite). |
| 11 | `repeat_if_wrong`| bool | `1` or `0` | Repeat stimulus if missed/wrong. |

---

## 2. Event Messages (Firmware ➔ App)

`EVT` messages provide real-time feedback to the App during the exercise.

### A. Sensor Activated (ON)
Sent when a sensor lights up as a target.
`EVT|ON|stimuli_mode|sensor_id|stimuli_color|dist_qty|dist_colors`
*Example:* `EVT|ON|1|2|00ff00|0|0`

### B. Correct Hit (HIT)
Sent when the athlete hits the correct target.
`EVT|HIT|stimuli_mode|sensor_id|reaction_time`
*Example:* `EVT|HIT|1|4|992`

### C. Error or Failure (MISS)
Sent when the stimulus is not hit correctly.
`EVT|MISS|stimuli_mode|sensor_id|err_type|wrong_sensor_id`

* **Type 1 (TIMEOUT):** Time ran out. `wrong_sensor_id` is always `0`.
    * *Example:* `EVT|MISS|1|9|1|0`
* **Type 2 (WRONG):** Athlete hit the wrong sensor. `wrong_sensor_id` indicates which one was hit.
    * *Example:* `EVT|MISS|1|9|2|10`

---

## 🚀 Test Templates (V1.0.0)

### Lite Light Tap
`SET|14|1|1|00FF00|0|0|1|1000|1000|0|0`

### Rapid Response
`SET|20|1|1|00FF00|0|0|2|400|900|1200|0`

---

## 🛠️ Implementation Notes

* **Zero Rule:** The value `0` is used universally to represent "Null", "None", or "Disabled" (replaces `none` or `000000`).
* **Stateless Design:** Every `EVT` includes the `stimuli_mode` so the App can process data correctly even if it loses internal state sync.
* **Consistency:** Ensure the App sends hex colors without the `#` prefix to match the firmware's expectations.