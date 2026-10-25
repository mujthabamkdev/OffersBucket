import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/offersbucket_mark.png',
    width: size,
    height: size,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.high,
  );
}

class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AppBrandMark(),
      const SizedBox(width: 10),
      Flexible(
        child: Text.rich(
          const TextSpan(
            children: [
              TextSpan(
                text: 'Offers',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: 'Bucket',
                style: TextStyle(fontWeight: FontWeight.w300),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: AppColors.ink,
            fontSize: fontSize,
            letterSpacing: .5,
          ),
        ),
      ),
    ],
  );
}
