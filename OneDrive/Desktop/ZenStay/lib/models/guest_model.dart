/// Model for a guest row in the authorization letter.
class GuestModel {
  final String name;
  final String proofOfId;
  final String relationship;

  const GuestModel({
    required this.name,
    required this.proofOfId,
    required this.relationship,
  });

  GuestModel copyWith({
    String? name,
    String? proofOfId,
    String? relationship,
  }) {
    return GuestModel(
      name: name ?? this.name,
      proofOfId: proofOfId ?? this.proofOfId,
      relationship: relationship ?? this.relationship,
    );
  }
}
