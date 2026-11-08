import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Horizontal scrollable row of pill filters for sorting recordings.
class TimeFilterSelector extends StatelessWidget {
  const TimeFilterSelector({
    super.key,
    required this.filters,
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  final List<String> filters;
  final String selectedFilter;
  final ValueChanged<String> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = filter == selectedFilter;

          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (_) => onFilterSelected(filter),
            showCheckmark: false,
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            backgroundColor: isDark
                ? AppColors.surfaceContainerDark
                : AppColors.surfaceContainerLight,
            selectedColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? AppColors.accent
                    : (isDark ? AppColors.borderDark : AppColors.borderLight),
                width: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}
