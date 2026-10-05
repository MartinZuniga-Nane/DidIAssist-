import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class Course extends Equatable {
  Course({
    required this.id,
    required this.name,
    this.activeFrom,
    this.activeUntil,
  }) {
    requireNonBlank(id, 'id');
    requireNonBlank(name, 'name');
    if (activeFrom != null &&
        activeUntil != null &&
        activeUntil!.compareTo(activeFrom!) < 0) {
      throw ArgumentError('activeUntil must not precede activeFrom.');
    }
  }

  final String id;
  final String name;
  final LocalDate? activeFrom;
  final LocalDate? activeUntil;

  bool isActiveOn(LocalDate date) =>
      (activeFrom == null || date.compareTo(activeFrom!) >= 0) &&
      (activeUntil == null || date.compareTo(activeUntil!) <= 0);

  // Nullable fields use callbacks so omission preserves and () => null clears.
  Course copyWith({
    String? id,
    String? name,
    LocalDate? Function()? activeFrom,
    LocalDate? Function()? activeUntil,
  }) => Course(
    id: id ?? this.id,
    name: name ?? this.name,
    activeFrom: activeFrom == null ? this.activeFrom : activeFrom(),
    activeUntil: activeUntil == null ? this.activeUntil : activeUntil(),
  );

  @override
  List<Object?> get props => [id, name, activeFrom, activeUntil];
}
