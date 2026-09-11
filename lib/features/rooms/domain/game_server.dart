class GameWorld {
  const GameWorld({required this.id, required this.name});

  final String id;
  final String name;

  List<GameServer> get servers => [
        for (var number = 1; number <= 10; number++)
          GameServer(world: this, number: number),
      ];
}

class GameServer {
  const GameServer({required this.world, required this.number});

  final GameWorld world;
  final int number;

  String get id => '${world.id}-${number.toString().padLeft(2, '0')}';
  String get label => '${world.name} ${number.toString().padLeft(2, '0')}';
}

const gameWorlds = [
  GameWorld(id: 'dien', name: '디엔'),
  GameWorld(id: 'lindriss', name: '린드리스'),
  GameWorld(id: 'ulan', name: '울란'),
  GameWorld(id: 'garbana', name: '가르바나'),
];
