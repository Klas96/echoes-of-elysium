import 'package:flutter/material.dart';

import 'room_services.dart';

/// HUD chip for Dao's active meal bonus and its time left (#31). Only one
/// meal is active at a time; a new bowl replaces it. Sits under the
/// well-rested chip and follows its compact layout.
class MealChip extends StatelessWidget {
  const MealChip({super.key});

  static const color = Color(0xFFFF9E5A);

  static String bonusLabel(String id) => switch (id) {
        'ember_broth' => 'REGEN x${Meals.regenBoost.round()}',
        'moss_noodles' => '+${((Meals.speedBoost - 1) * 100).round()}% SPEED',
        'night_bowl' => 'NIGHT SIGHT',
        _ => '',
      };

  static String timeLabel(double left) {
    final s = left.ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Meals.active, Meals.remaining]),
      builder: (_, __) {
        final meal = Meals.byId(Meals.active.value);
        final left = Meals.remaining.value;
        if (meal == null || left <= 0) return const SizedBox.shrink();
        final narrow = MediaQuery.sizeOf(context).width < 440;
        final title = Text('${meal.name.toUpperCase()}  ${timeLabel(left)}',
            style: const TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2));
        final bonus = Text(bonusLabel(meal.id),
            style: const TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 0.8));
        return Padding(
          key: const ValueKey('hud-meal'),
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              border: Border.all(color: color.withValues(alpha: 0.7)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.ramen_dining, size: 11, color: color),
              const SizedBox(width: 4),
              if (narrow)
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  title,
                  const SizedBox(height: 1),
                  bonus,
                ])
              else ...[
                title,
                const SizedBox(width: 8),
                bonus,
              ],
            ]),
          ),
        );
      },
    );
  }
}
