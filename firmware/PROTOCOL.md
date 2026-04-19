# 🛰️ Serial Communication Protocol - V1.0.0 (Full Symmetry)

This document defines the communication contract between the App (Control Center) and the Firmware (Sensors). The JSON structure in the App and the Serial string in the Firmware are now fully mirrored for perfect synchronization.

## 1. Configuration Command (`SET`)

The `SET` command initializes exercise parameters using a pipe-delimited (`|`) string.

**Format:**
`SET|stimuli_count|stimuli_rounds|stimuli_mode|stimuli_color|dist_qty|dist_colors|delay_type|delay_min|delay_max|timeout_ms|repeat_if_wrong`

### 📋 Parameter Mapping

| Index | Field Name | JSON Type | Serial Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `stimuli_count` | integer | `int` | Hits required per round to finish. |
| 2 | `stimuli_rounds` | integer | `int` | Total number of sets/rounds to repeat. |
| 3 | `stimuli_mode` | integer | `1` or `2` | **1**: Random, **2**: Pattern (Coordination). |
| 4 | `stimuli_color` | string | `hex` | Target color (e.g., 00FF00). No '#' prefix. |
| 5 | `dist_qty` | integer | `int` | Number of active distractors (0-3). |
| 6 | `dist_colors` | array/string | `list/0` | HEX list (comma-separated) or `0`. |
| 7 | `delay_type` | integer | `1` or `2` | **1**: Fixed, **2**: Range. |
| 8 | `delay_min` | integer | `ms` | Minimum delay before next stimulus. |
| 9 | `delay_max` | integer | `ms` | Maximum delay (equal to min if fixed). |
| 10 | `timeout_ms` | integer | `ms` | Time limit to hit sensor (0: infinite). |
| 11 | `repeat_if_wrong`| boolean | `1` or `0` | **1**: True, **0**: False (Repeat on error). |

---

## 🚀 Validated Exercise Templates

Use these strings to test the firmware via the Serial Monitor:

### 1. Lite Light Tap
`SET|14|1|1|00FF00|0|0|1|1000|1000|0|0`

### 2. Rapid Response
`SET|20|1|1|00FF00|0|0|2|400|900|1200|0`

### 3. Neural Blitz
`SET|30|1|1|00FF00|0|0|2|200|600|750|1`

### 4. Focus Filter
`SET|15|1|1|00FF00|1|FF0000|1|800|800|1200|0`

### 5. Peripheral Chaos
`SET|20|1|1|00FF00|2|FF0000,0000FF|2|500|1000|1000|0`

### 6. Split-Second Choice
`SET|25|1|1|00FF00|3|FF0000,FFFF00,FFFFFF|2|300|700|800|1`

---

## 🛠️ Implementation Guide

### Firmware Parser (C++)
Since the protocol is numeric and positional, use `strtok()` to extract tokens:
- Use `atoi(token)` for most fields to save memory and CPU cycles.
- For `dist_colors` (index 6), check if the value is `"0"` to skip distractor logic.

### App Mapper (Data Sync)
- Ensure the keys in the `parameters` object are serialized in the exact order shown above.
- Convert hex colors to strings without the `#` symbol.
- Booleans must be cast to `1` or `0` before transmission.

---
*Last Updated: April 2026*