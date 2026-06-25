class EvaluationResult {
  final int roundNum;
  final int attemptNum;
  final int stimulusStart;
  final int stimulusEnd;
  final int reactionTime;
  final int gct;
  final int delayApplied;
  final List<int> targets;          // IDs dos alvos ativos, ex: [1, 10, 5]
  final String targetColorHex;            // Cor dos alvos, ex: "#00FF00"
  final List<int> distractors;      // IDs dos distratores ativos, ex: [11, 4, 6] (vazia se não houver)
  final List<String> distractorColorsHex; // Cores dos distratores, ex: ["#FF0000", "#FF0000"]
  final int hitSensorId;                  // ID do pod que sofreu o toque (0 se for Timeout)
  final int errorType;                    // 0 = Hit, 1 = Wrong Sensor, 2 = Timeout

  EvaluationResult({
    required this.roundNum,
    required this.attemptNum,
    required this.stimulusStart,
    required this.stimulusEnd,
    required this.reactionTime,
    required this.gct,
    required this.delayApplied,
    required this.targets,
    required this.targetColorHex,
    required this.distractors,
    required this.distractorColorsHex,
    required this.hitSensorId,
    required this.errorType,
  });

  Map<String, dynamic> toMap() {
    return {
      'round_num': roundNum,
      'attempt_num': attemptNum,
      'stimulus_start': stimulusStart,
      'stimulus_end': stimulusEnd,
      'reaction_time': reactionTime,
      'gct': gct,
      'delay_applied': delayApplied,
      'targets': targets.join(','),
      'target_color_hex': targetColorHex,
      'distractors': distractors.join(','),
      'distractor_colors_hex': distractorColorsHex.join(','),
      'hit_sensor_id': hitSensorId,
      'error_type': errorType,
    };
  }

  factory EvaluationResult.fromMap(Map<String, dynamic> map) {
    return EvaluationResult(
      roundNum: map['round_num'] as int,
      attemptNum: map['attempt_num'] as int,
      stimulusStart: map['stimulus_start'] as int,
      stimulusEnd: map['stimulus_end'] as int,
      reactionTime: map['reaction_time'] as int,
      gct: map['gct'] as int,
      delayApplied: map['delay_applied'] as int,
      targets: (map['targets'] as String).split(',').map(int.parse).toList(),
      targetColorHex: map['target_color_hex'] as String,
      distractors: (map['distractors'] as String).isEmpty
          ? []
          : (map['distractors'] as String).split(',').map(int.parse).toList(),
      distractorColorsHex: (map['distractor_colors_hex'] as String).isEmpty
          ? []
          : (map['distractor_colors_hex'] as String).split(',').toList(),

      hitSensorId: map['hit_sensor_id'] as int,
      errorType: map['error_type'] as int,
    );
  }
}