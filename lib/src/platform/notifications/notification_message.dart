import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class NotificationMessage extends Equatable {
  const NotificationMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  List<Object> get props => [title, body];
}
