/// CircleOpening — angular gap on a circle_wall or gazebo_roof.
class CircleOpening {
  final double angle;
  final double width;
  final String id;

  const CircleOpening({
    required this.angle,
    required this.width,
    required this.id,
  });

  factory CircleOpening.fromJson(Map<String, dynamic> json) {
    return CircleOpening(
      angle: (json['angle'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      id: json['id'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'angle': angle,
        'width': width,
        'id': id,
      };
}
