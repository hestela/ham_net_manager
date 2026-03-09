class Person {
  /// 0 means unsaved (not yet in the database).
  final int id;
  final String firstName;
  final String? lastName;
  final String? fccCallsign;
  final String? gmrsCallsign;
  final bool isMember;
  final bool isActive;
  final String? city;
  final String? neighborhood;

  const Person({
    this.id = 0,
    required this.firstName,
    this.lastName,
    this.fccCallsign,
    this.gmrsCallsign,
    this.isMember = false,
    this.isActive = true,
    this.city,
    this.neighborhood,
  });

  /// e.g. "Bob H" or "Kelly A"
  String get displayName {
    if (lastName != null && lastName!.isNotEmpty) {
      return '$firstName ${lastName![0]}';
    }
    return firstName;
  }

  /// e.g. "Bob H/KD234" — used in net roles cells
  String get roleLabel => '$displayName/${fccCallsign ?? '?'}';

  factory Person.fromMap(Map<String, dynamic> m) => Person(
        id: m['id'] as int,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String?,
        fccCallsign: m['fcc_callsign'] as String?,
        gmrsCallsign: m['gmrs_callsign'] as String?,
        isMember: (m['is_member'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        city: m['city'] as String?,
        neighborhood: m['neighborhood'] as String?,
      );

  /// All fields except id — used for INSERT and UPDATE.
  Map<String, dynamic> toMap() => {
        'first_name': firstName,
        'last_name': lastName,
        'fcc_callsign': fccCallsign,
        'gmrs_callsign': gmrsCallsign,
        'is_member': isMember ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'city': city,
        'neighborhood': neighborhood,
      };

  Person copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? fccCallsign,
    String? gmrsCallsign,
    bool? isMember,
    bool? isActive,
    String? city,
    String? neighborhood,
  }) =>
      Person(
        id: id ?? this.id,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        fccCallsign: fccCallsign ?? this.fccCallsign,
        gmrsCallsign: gmrsCallsign ?? this.gmrsCallsign,
        isMember: isMember ?? this.isMember,
        isActive: isActive ?? this.isActive,
        city: city ?? this.city,
        neighborhood: neighborhood ?? this.neighborhood,
      );
}
