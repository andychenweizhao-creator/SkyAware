import 'dart:async';

class RadarAnimation{
  Timer? _radarTimer;
  int _radarFrameIndex = 10; // 0 to 10. 10 is current.
  bool _isRadarPlaying = true;
  // Frame 0 is -50min, Frame 1 is -45min, ..., Frame 10 is Current
  final List<String> _radarFrames = [
    'nexrad-n0q-900913-m50', 'nexrad-n0q-900913-m45',
    'nexrad-n0q-900913-m40', 'nexrad-n0q-900913-m35',
    'nexrad-n0q-900913-m30', 'nexrad-n0q-900913-m25',
    'nexrad-n0q-900913-m20', 'nexrad-n0q-900913-m15',
    'nexrad-n0q-900913-m10', 'nexrad-n0q-900913-m05',
    'nexrad-n0q-900913', // Current
  ];

  void start({
    required bool Function() shouldAnimate,

  }){
    _radarTimer?.cancel();
    _radarTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!shouldAnimate() || !_isRadarPlaying) {
        return;
      }
        _radarFrameIndex++;
        if (_radarFrameIndex >= _radarFrames.length) {
          _radarFrameIndex = 0;
        }
      }
    );
  }

  void toggle(){
        _isRadarPlaying = !_isRadarPlaying;
  }

  void dispose(){
        _radarTimer?.cancel();
      }

}
