import 'package:moor/moor.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/dao/tag_helper.dart';
import 'package:potato_notes/data/model/image_list.dart';
import 'package:potato_notes/data/model/list_content.dart';
import 'package:potato_notes/data/model/reminder_list.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/data/model/tag_list.dart';

part 'database.g.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  DateTimeColumn get creationDate => dateTime()();
  DateTimeColumn get lastModifyDate => dateTime()();
  IntColumn get color => integer().withDefault(const Constant(0))();
  TextColumn get images => text().map(const ImageListConverter())();
  BoolColumn get list => boolean().withDefault(const Constant(false))();
  TextColumn get listContent => text().map(const ListContentConverter())();
  TextColumn get reminders => text().map(const ReminderListConverter())();
  TextColumn get tags => text().map(const TagListConverter())();
  BoolColumn get hideContent => boolean().withDefault(const Constant(false))();
  BoolColumn get lockNote => boolean().withDefault(const Constant(false))();
  BoolColumn get usesBiometrics =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get lastModifyDate => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@UseMoor(tables: [Notes, Tags], daos: [NoteHelper, TagHelper])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 6;
}
