import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper that adds a spring animation and haptic feedback on tap.
class SpringButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const SpringButton({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<SpringButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse(from: _controller.value);
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// A wrapper that animates its child into view with a slide and fade effect.
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final double offset;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 50),
    this.offset = 20.0,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, widget.offset), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(widget.delay * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: _slideAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Animates a number from 0 to [value].
class AnimatedCounter extends StatelessWidget {
  final num value;
  final TextStyle style;
  final String suffix;
  final int fractionDigits;

  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.suffix = "",
    this.fractionDigits = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutExpo,
      builder: (context, animatedValue, child) {
        return Text(
          "${animatedValue.toStringAsFixed(fractionDigits)}$suffix",
          style: style,
        );
      },
    );
  }
}

/// A background that breathes by animating a gradient's alignment.
class AliveBackground extends StatefulWidget {
  final Gradient gradient;
  final Widget? child;

  const AliveBackground({
    super.key,
    required this.gradient,
    this.child,
  });

  @override
  State<AliveBackground> createState() => _AliveBackgroundState();
}

class _AliveBackgroundState extends State<AliveBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We assume the gradient is a LinearGradient to animate alignment.
    // If it's not, we just use it as is, but assuming LinearGradient for the effect.
    final originalGradient = widget.gradient as LinearGradient;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: originalGradient.colors,
              begin: Alignment.topLeft.add(Alignment(0, _controller.value * 0.2)),
              end: Alignment.bottomRight.add(Alignment(0, -_controller.value * 0.2)),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
