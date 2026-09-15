class RoomMember {
  const RoomMember({
    required this.uid,
    required this.displayName,
    required this.role,
    this.pushEnabled = true,
  });

  final String uid;
  final String displayName;
  final String role;
  final bool pushEnabled;

  bool get isOwner => role == 'owner';
  bool get canEditSettings => role == 'owner' || role == 'editor';

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
        uid: json['uid'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '사용자',
        role: json['role'] as String? ?? 'member',
        pushEnabled: json['pushEnabled'] as bool? ?? true,
      );
}
