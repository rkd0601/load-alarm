class BossRoom {
  const BossRoom({
    required this.id,
    required this.name,
    required this.world,
    required this.worldName,
    required this.serverNo,
    required this.ownerUid,
    required this.hasPassword,
  });

  final String id;
  final String name;
  final String world;
  final String worldName;
  final int serverNo;
  final String ownerUid;
  final bool hasPassword;

  String get serverLabel => '$worldName ${serverNo.toString().padLeft(2, '0')}';

  factory BossRoom.fromJson(String id, Map<String, dynamic> json) => BossRoom(
        id: id,
        name: json['name'] as String? ?? '',
        world: json['world'] as String? ?? '',
        worldName: json['worldName'] as String? ?? '',
        serverNo: json['serverNo'] as int? ?? 0,
        ownerUid: json['ownerUid'] as String? ?? '',
        hasPassword: json['hasPassword'] as bool? ?? false,
      );
}
