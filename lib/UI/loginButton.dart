import 'package:flutter/material.dart';

class loginButton extends StatelessWidget {
  final String text;
  final String? imagePath;
  final IconData? iconData;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback? onPressed;

  const loginButton({
    super.key,
    required this.text,
    this.imagePath,
    this.iconData,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed ?? () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          side: backgroundColor == Colors.white 
              ? BorderSide(color: Colors.grey.withValues(alpha: 0.2)) 
              : BorderSide.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imagePath != null) ...[
              Image.asset(imagePath!, height: 24),
              const SizedBox(width: 12),
            ],
            if (iconData != null) ...[
              Icon(iconData, color: textColor, size: 24),
              const SizedBox(width: 12),
            ],
            
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
