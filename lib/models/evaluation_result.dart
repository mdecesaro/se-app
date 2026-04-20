class EvaluationResult {
  final int roundNum;
  final int stimulusId;
  final String stimulusPosition;
  final String stimulusType;
  final String correctColor;
  final int reactionTime;
  final int stimulusStart;
  final int stimulusEnd;
  final int error;
  final String footUsed;
  final int wrongSensorId;
  final String? distractorType;
  final List<Map<String, dynamic>> distractorIdColor;

  EvaluationResult({
    required this.roundNum,
    required this.stimulusId,
    required this.stimulusPosition,
    required this.stimulusType,
    required this.correctColor,
    required this.reactionTime,
    required this.stimulusStart,
    required this.stimulusEnd,
    required this.error,
    required this.footUsed,
    required this.wrongSensorId,
    this.distractorType,
    required this.distractorIdColor,
  });

  Map<String, dynamic> toMap() {
    return {
      'round_num': roundNum,
      'stimulus_id': stimulusId,
      'stimulus_position': stimulusPosition,
      'stimulus_type': stimulusType,
      'correct_color': correctColor,
      'reaction_time': reactionTime,
      'stimulus_start': stimulusStart,
      'stimulus_end': stimulusEnd,
      'error': error,
      'foot_used': footUsed,
      'wrong_sensor_id': wrongSensorId,
      'distractor_type': distractorType,
      'distractor_id_color': distractorIdColor,
    };
  }
}
