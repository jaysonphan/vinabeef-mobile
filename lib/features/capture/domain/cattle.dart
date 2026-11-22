/// An open scheduled dose (herd-health `OpenSchedule`). Dose number is optional: the server
/// schedule only carries vaccine code + due time.
class VaccinationSchedule {
  const VaccinationSchedule({
    required this.scheduleId,
    required this.vaccineCode,
    this.doseNumber,
    this.dueDate,
  });

  final String scheduleId;
  final String vaccineCode;
  final int? doseNumber;

  /// ISO date/time string as returned by the server (`dueAt`).
  final String? dueDate;

  factory VaccinationSchedule.fromJson(Map<String, dynamic> j) => VaccinationSchedule(
        scheduleId: j['scheduleId'] as String,
        vaccineCode: j['vaccineCode'] as String,
        doseNumber: (j['doseNumber'] as num?)?.toInt(),
        dueDate: (j['dueAt'] ?? j['dueDate']) as String?,
      );

  Map<String, Object?> toJson() => {
        'scheduleId': scheduleId,
        'vaccineCode': vaccineCode,
        'doseNumber': doseNumber,
        'dueAt': dueDate,
      };

  String get label {
    final due = dueDate == null ? '' : ' (due ${dueDate!.length >= 10 ? dueDate!.substring(0, 10) : dueDate})';
    final dose = doseNumber == null ? '' : ' – dose $doseNumber';
    return '$vaccineCode$dose$due';
  }
}

/// Minimal cattle view cached in a work session (herd-health `CattleInScope`).
/// Not the clinical history.
class Cattle {
  const Cattle({
    required this.cattleId,
    required this.rfid,
    required this.name,
    required this.farmId,
    required this.barnId,
    this.farmName,
    this.resourceVersion = 0,
    this.custodyVersion = 0,
    this.schedules = const [],
  });

  final String cattleId;

  /// Permanent ear-tag RFID.
  final String rfid;
  final String name;
  final String farmId;
  final String? farmName;
  final String barnId;

  /// Server optimistic-concurrency version of the animal. Sent as `expectedVersion`; if another
  /// record was accepted for this animal in between, the server answers NEEDS_REVIEW.
  final int resourceVersion;
  final int custodyVersion;
  final List<VaccinationSchedule> schedules;

  String get label => '$name · $rfid';
  String get location => '$farmId / $barnId';

  Cattle copyWith({int? resourceVersion, List<VaccinationSchedule>? schedules}) => Cattle(
        cattleId: cattleId,
        rfid: rfid,
        name: name,
        farmId: farmId,
        farmName: farmName,
        barnId: barnId,
        resourceVersion: resourceVersion ?? this.resourceVersion,
        custodyVersion: custodyVersion,
        schedules: schedules ?? this.schedules,
      );

  factory Cattle.fromJson(Map<String, dynamic> j) => Cattle(
        cattleId: j['cattleId'] as String,
        rfid: (j['rfid'] ?? j['permanentRfid']) as String,
        name: (j['displayName'] ?? j['name'] ?? j['cattleId']) as String,
        farmId: j['farmId'] as String,
        farmName: j['farmName'] as String?,
        barnId: j['barnId'] as String,
        resourceVersion: (j['resourceVersion'] as num?)?.toInt() ?? 0,
        custodyVersion: (j['custodyVersion'] as num?)?.toInt() ?? 0,
        schedules: ((j['openSchedules'] ?? j['schedules']) as List? ?? const [])
            .map((e) => VaccinationSchedule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, Object?> toJson() => {
        'cattleId': cattleId,
        'rfid': rfid,
        'displayName': name,
        'farmId': farmId,
        'farmName': farmName,
        'barnId': barnId,
        'resourceVersion': resourceVersion,
        'custodyVersion': custodyVersion,
        'openSchedules': schedules.map((s) => s.toJson()).toList(),
      };
}
