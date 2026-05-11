// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SongsTable extends Songs with TableInfo<$SongsTable, SongRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<String> mood = GeneratedColumn<String>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localLyricsPathMeta = const VerificationMeta(
    'localLyricsPath',
  );
  @override
  late final GeneratedColumn<String> localLyricsPath = GeneratedColumn<String>(
    'local_lyrics_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localArtworkPathMeta = const VerificationMeta(
    'localArtworkPath',
  );
  @override
  late final GeneratedColumn<String> localArtworkPath = GeneratedColumn<String>(
    'local_artwork_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<String> addedAt = GeneratedColumn<String>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<String> lastPlayedAt = GeneratedColumn<String>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<int> isFavorite = GeneratedColumn<int>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    artist,
    album,
    genre,
    mood,
    bpm,
    durationMs,
    fileName,
    localFilePath,
    localLyricsPath,
    localArtworkPath,
    searchText,
    addedAt,
    lastPlayedAt,
    isFavorite,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localFilePathMeta);
    }
    if (data.containsKey('local_lyrics_path')) {
      context.handle(
        _localLyricsPathMeta,
        localLyricsPath.isAcceptableOrUnknown(
          data['local_lyrics_path']!,
          _localLyricsPathMeta,
        ),
      );
    }
    if (data.containsKey('local_artwork_path')) {
      context.handle(
        _localArtworkPathMeta,
        localArtworkPath.isAcceptableOrUnknown(
          data['local_artwork_path']!,
          _localArtworkPathMeta,
        ),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SongRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mood'],
      ),
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      localLyricsPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_lyrics_path'],
      ),
      localArtworkPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_artwork_path'],
      ),
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_at'],
      ),
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_played_at'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_favorite'],
      )!,
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class SongRow extends DataClass implements Insertable<SongRow> {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? mood;
  final int? bpm;
  final int? durationMs;
  final String? fileName;
  final String localFilePath;
  final String? localLyricsPath;
  final String? localArtworkPath;
  final String? searchText;
  final String? addedAt;
  final String? lastPlayedAt;
  final int isFavorite;
  const SongRow({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.genre,
    this.mood,
    this.bpm,
    this.durationMs,
    this.fileName,
    required this.localFilePath,
    this.localLyricsPath,
    this.localArtworkPath,
    this.searchText,
    this.addedAt,
    this.lastPlayedAt,
    required this.isFavorite,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(mood);
    }
    if (!nullToAbsent || bpm != null) {
      map['bpm'] = Variable<int>(bpm);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    map['local_file_path'] = Variable<String>(localFilePath);
    if (!nullToAbsent || localLyricsPath != null) {
      map['local_lyrics_path'] = Variable<String>(localLyricsPath);
    }
    if (!nullToAbsent || localArtworkPath != null) {
      map['local_artwork_path'] = Variable<String>(localArtworkPath);
    }
    if (!nullToAbsent || searchText != null) {
      map['search_text'] = Variable<String>(searchText);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<String>(addedAt);
    }
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<String>(lastPlayedAt);
    }
    map['is_favorite'] = Variable<int>(isFavorite);
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      title: Value(title),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      bpm: bpm == null && nullToAbsent ? const Value.absent() : Value(bpm),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      localFilePath: Value(localFilePath),
      localLyricsPath: localLyricsPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localLyricsPath),
      localArtworkPath: localArtworkPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localArtworkPath),
      searchText: searchText == null && nullToAbsent
          ? const Value.absent()
          : Value(searchText),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      isFavorite: Value(isFavorite),
    );
  }

  factory SongRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      genre: serializer.fromJson<String?>(json['genre']),
      mood: serializer.fromJson<String?>(json['mood']),
      bpm: serializer.fromJson<int?>(json['bpm']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      localLyricsPath: serializer.fromJson<String?>(json['localLyricsPath']),
      localArtworkPath: serializer.fromJson<String?>(json['localArtworkPath']),
      searchText: serializer.fromJson<String?>(json['searchText']),
      addedAt: serializer.fromJson<String?>(json['addedAt']),
      lastPlayedAt: serializer.fromJson<String?>(json['lastPlayedAt']),
      isFavorite: serializer.fromJson<int>(json['isFavorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'genre': serializer.toJson<String?>(genre),
      'mood': serializer.toJson<String?>(mood),
      'bpm': serializer.toJson<int?>(bpm),
      'durationMs': serializer.toJson<int?>(durationMs),
      'fileName': serializer.toJson<String?>(fileName),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'localLyricsPath': serializer.toJson<String?>(localLyricsPath),
      'localArtworkPath': serializer.toJson<String?>(localArtworkPath),
      'searchText': serializer.toJson<String?>(searchText),
      'addedAt': serializer.toJson<String?>(addedAt),
      'lastPlayedAt': serializer.toJson<String?>(lastPlayedAt),
      'isFavorite': serializer.toJson<int>(isFavorite),
    };
  }

  SongRow copyWith({
    String? id,
    String? title,
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<String?> mood = const Value.absent(),
    Value<int?> bpm = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> fileName = const Value.absent(),
    String? localFilePath,
    Value<String?> localLyricsPath = const Value.absent(),
    Value<String?> localArtworkPath = const Value.absent(),
    Value<String?> searchText = const Value.absent(),
    Value<String?> addedAt = const Value.absent(),
    Value<String?> lastPlayedAt = const Value.absent(),
    int? isFavorite,
  }) => SongRow(
    id: id ?? this.id,
    title: title ?? this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    genre: genre.present ? genre.value : this.genre,
    mood: mood.present ? mood.value : this.mood,
    bpm: bpm.present ? bpm.value : this.bpm,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    fileName: fileName.present ? fileName.value : this.fileName,
    localFilePath: localFilePath ?? this.localFilePath,
    localLyricsPath: localLyricsPath.present
        ? localLyricsPath.value
        : this.localLyricsPath,
    localArtworkPath: localArtworkPath.present
        ? localArtworkPath.value
        : this.localArtworkPath,
    searchText: searchText.present ? searchText.value : this.searchText,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    isFavorite: isFavorite ?? this.isFavorite,
  );
  SongRow copyWithCompanion(SongsCompanion data) {
    return SongRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      genre: data.genre.present ? data.genre.value : this.genre,
      mood: data.mood.present ? data.mood.value : this.mood,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      localLyricsPath: data.localLyricsPath.present
          ? data.localLyricsPath.value
          : this.localLyricsPath,
      localArtworkPath: data.localArtworkPath.present
          ? data.localArtworkPath.value
          : this.localArtworkPath,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('genre: $genre, ')
          ..write('mood: $mood, ')
          ..write('bpm: $bpm, ')
          ..write('durationMs: $durationMs, ')
          ..write('fileName: $fileName, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('localLyricsPath: $localLyricsPath, ')
          ..write('localArtworkPath: $localArtworkPath, ')
          ..write('searchText: $searchText, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('isFavorite: $isFavorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    album,
    genre,
    mood,
    bpm,
    durationMs,
    fileName,
    localFilePath,
    localLyricsPath,
    localArtworkPath,
    searchText,
    addedAt,
    lastPlayedAt,
    isFavorite,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.genre == this.genre &&
          other.mood == this.mood &&
          other.bpm == this.bpm &&
          other.durationMs == this.durationMs &&
          other.fileName == this.fileName &&
          other.localFilePath == this.localFilePath &&
          other.localLyricsPath == this.localLyricsPath &&
          other.localArtworkPath == this.localArtworkPath &&
          other.searchText == this.searchText &&
          other.addedAt == this.addedAt &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.isFavorite == this.isFavorite);
}

class SongsCompanion extends UpdateCompanion<SongRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<String?> genre;
  final Value<String?> mood;
  final Value<int?> bpm;
  final Value<int?> durationMs;
  final Value<String?> fileName;
  final Value<String> localFilePath;
  final Value<String?> localLyricsPath;
  final Value<String?> localArtworkPath;
  final Value<String?> searchText;
  final Value<String?> addedAt;
  final Value<String?> lastPlayedAt;
  final Value<int> isFavorite;
  final Value<int> rowid;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.genre = const Value.absent(),
    this.mood = const Value.absent(),
    this.bpm = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.fileName = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.localLyricsPath = const Value.absent(),
    this.localArtworkPath = const Value.absent(),
    this.searchText = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongsCompanion.insert({
    required String id,
    required String title,
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.genre = const Value.absent(),
    this.mood = const Value.absent(),
    this.bpm = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.fileName = const Value.absent(),
    required String localFilePath,
    this.localLyricsPath = const Value.absent(),
    this.localArtworkPath = const Value.absent(),
    this.searchText = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       localFilePath = Value(localFilePath);
  static Insertable<SongRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? genre,
    Expression<String>? mood,
    Expression<int>? bpm,
    Expression<int>? durationMs,
    Expression<String>? fileName,
    Expression<String>? localFilePath,
    Expression<String>? localLyricsPath,
    Expression<String>? localArtworkPath,
    Expression<String>? searchText,
    Expression<String>? addedAt,
    Expression<String>? lastPlayedAt,
    Expression<int>? isFavorite,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (genre != null) 'genre': genre,
      if (mood != null) 'mood': mood,
      if (bpm != null) 'bpm': bpm,
      if (durationMs != null) 'duration_ms': durationMs,
      if (fileName != null) 'file_name': fileName,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (localLyricsPath != null) 'local_lyrics_path': localLyricsPath,
      if (localArtworkPath != null) 'local_artwork_path': localArtworkPath,
      if (searchText != null) 'search_text': searchText,
      if (addedAt != null) 'added_at': addedAt,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<String?>? genre,
    Value<String?>? mood,
    Value<int?>? bpm,
    Value<int?>? durationMs,
    Value<String?>? fileName,
    Value<String>? localFilePath,
    Value<String?>? localLyricsPath,
    Value<String?>? localArtworkPath,
    Value<String?>? searchText,
    Value<String?>? addedAt,
    Value<String?>? lastPlayedAt,
    Value<int>? isFavorite,
    Value<int>? rowid,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      mood: mood ?? this.mood,
      bpm: bpm ?? this.bpm,
      durationMs: durationMs ?? this.durationMs,
      fileName: fileName ?? this.fileName,
      localFilePath: localFilePath ?? this.localFilePath,
      localLyricsPath: localLyricsPath ?? this.localLyricsPath,
      localArtworkPath: localArtworkPath ?? this.localArtworkPath,
      searchText: searchText ?? this.searchText,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (mood.present) {
      map['mood'] = Variable<String>(mood.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (localLyricsPath.present) {
      map['local_lyrics_path'] = Variable<String>(localLyricsPath.value);
    }
    if (localArtworkPath.present) {
      map['local_artwork_path'] = Variable<String>(localArtworkPath.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<String>(addedAt.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<String>(lastPlayedAt.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<int>(isFavorite.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('genre: $genre, ')
          ..write('mood: $mood, ')
          ..write('bpm: $bpm, ')
          ..write('durationMs: $durationMs, ')
          ..write('fileName: $fileName, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('localLyricsPath: $localLyricsPath, ')
          ..write('localArtworkPath: $localArtworkPath, ')
          ..write('searchText: $searchText, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SongStatsTable extends SongStats
    with TableInfo<$SongStatsTable, SongStatsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completeCountMeta = const VerificationMeta(
    'completeCount',
  );
  @override
  late final GeneratedColumn<int> completeCount = GeneratedColumn<int>(
    'complete_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skipCountMeta = const VerificationMeta(
    'skipCount',
  );
  @override
  late final GeneratedColumn<int> skipCount = GeneratedColumn<int>(
    'skip_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _replayCountMeta = const VerificationMeta(
    'replayCount',
  );
  @override
  late final GeneratedColumn<int> replayCount = GeneratedColumn<int>(
    'replay_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _favoriteCountMeta = const VerificationMeta(
    'favoriteCount',
  );
  @override
  late final GeneratedColumn<int> favoriteCount = GeneratedColumn<int>(
    'favorite_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalListenedMsMeta = const VerificationMeta(
    'totalListenedMs',
  );
  @override
  late final GeneratedColumn<int> totalListenedMs = GeneratedColumn<int>(
    'total_listened_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<String> lastPlayedAt = GeneratedColumn<String>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    playCount,
    completeCount,
    skipCount,
    replayCount,
    favoriteCount,
    totalListenedMs,
    lastPlayedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'song_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongStatsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('complete_count')) {
      context.handle(
        _completeCountMeta,
        completeCount.isAcceptableOrUnknown(
          data['complete_count']!,
          _completeCountMeta,
        ),
      );
    }
    if (data.containsKey('skip_count')) {
      context.handle(
        _skipCountMeta,
        skipCount.isAcceptableOrUnknown(data['skip_count']!, _skipCountMeta),
      );
    }
    if (data.containsKey('replay_count')) {
      context.handle(
        _replayCountMeta,
        replayCount.isAcceptableOrUnknown(
          data['replay_count']!,
          _replayCountMeta,
        ),
      );
    }
    if (data.containsKey('favorite_count')) {
      context.handle(
        _favoriteCountMeta,
        favoriteCount.isAcceptableOrUnknown(
          data['favorite_count']!,
          _favoriteCountMeta,
        ),
      );
    }
    if (data.containsKey('total_listened_ms')) {
      context.handle(
        _totalListenedMsMeta,
        totalListenedMs.isAcceptableOrUnknown(
          data['total_listened_ms']!,
          _totalListenedMsMeta,
        ),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId};
  @override
  SongStatsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongStatsRow(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      completeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}complete_count'],
      )!,
      skipCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skip_count'],
      )!,
      replayCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}replay_count'],
      )!,
      favoriteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorite_count'],
      )!,
      totalListenedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_listened_ms'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_played_at'],
      ),
    );
  }

  @override
  $SongStatsTable createAlias(String alias) {
    return $SongStatsTable(attachedDatabase, alias);
  }
}

class SongStatsRow extends DataClass implements Insertable<SongStatsRow> {
  final String songId;
  final int playCount;
  final int completeCount;
  final int skipCount;
  final int replayCount;
  final int favoriteCount;
  final int totalListenedMs;
  final String? lastPlayedAt;
  const SongStatsRow({
    required this.songId,
    required this.playCount,
    required this.completeCount,
    required this.skipCount,
    required this.replayCount,
    required this.favoriteCount,
    required this.totalListenedMs,
    this.lastPlayedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<String>(songId);
    map['play_count'] = Variable<int>(playCount);
    map['complete_count'] = Variable<int>(completeCount);
    map['skip_count'] = Variable<int>(skipCount);
    map['replay_count'] = Variable<int>(replayCount);
    map['favorite_count'] = Variable<int>(favoriteCount);
    map['total_listened_ms'] = Variable<int>(totalListenedMs);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<String>(lastPlayedAt);
    }
    return map;
  }

  SongStatsCompanion toCompanion(bool nullToAbsent) {
    return SongStatsCompanion(
      songId: Value(songId),
      playCount: Value(playCount),
      completeCount: Value(completeCount),
      skipCount: Value(skipCount),
      replayCount: Value(replayCount),
      favoriteCount: Value(favoriteCount),
      totalListenedMs: Value(totalListenedMs),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
    );
  }

  factory SongStatsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongStatsRow(
      songId: serializer.fromJson<String>(json['songId']),
      playCount: serializer.fromJson<int>(json['playCount']),
      completeCount: serializer.fromJson<int>(json['completeCount']),
      skipCount: serializer.fromJson<int>(json['skipCount']),
      replayCount: serializer.fromJson<int>(json['replayCount']),
      favoriteCount: serializer.fromJson<int>(json['favoriteCount']),
      totalListenedMs: serializer.fromJson<int>(json['totalListenedMs']),
      lastPlayedAt: serializer.fromJson<String?>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<String>(songId),
      'playCount': serializer.toJson<int>(playCount),
      'completeCount': serializer.toJson<int>(completeCount),
      'skipCount': serializer.toJson<int>(skipCount),
      'replayCount': serializer.toJson<int>(replayCount),
      'favoriteCount': serializer.toJson<int>(favoriteCount),
      'totalListenedMs': serializer.toJson<int>(totalListenedMs),
      'lastPlayedAt': serializer.toJson<String?>(lastPlayedAt),
    };
  }

  SongStatsRow copyWith({
    String? songId,
    int? playCount,
    int? completeCount,
    int? skipCount,
    int? replayCount,
    int? favoriteCount,
    int? totalListenedMs,
    Value<String?> lastPlayedAt = const Value.absent(),
  }) => SongStatsRow(
    songId: songId ?? this.songId,
    playCount: playCount ?? this.playCount,
    completeCount: completeCount ?? this.completeCount,
    skipCount: skipCount ?? this.skipCount,
    replayCount: replayCount ?? this.replayCount,
    favoriteCount: favoriteCount ?? this.favoriteCount,
    totalListenedMs: totalListenedMs ?? this.totalListenedMs,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
  );
  SongStatsRow copyWithCompanion(SongStatsCompanion data) {
    return SongStatsRow(
      songId: data.songId.present ? data.songId.value : this.songId,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      completeCount: data.completeCount.present
          ? data.completeCount.value
          : this.completeCount,
      skipCount: data.skipCount.present ? data.skipCount.value : this.skipCount,
      replayCount: data.replayCount.present
          ? data.replayCount.value
          : this.replayCount,
      favoriteCount: data.favoriteCount.present
          ? data.favoriteCount.value
          : this.favoriteCount,
      totalListenedMs: data.totalListenedMs.present
          ? data.totalListenedMs.value
          : this.totalListenedMs,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongStatsRow(')
          ..write('songId: $songId, ')
          ..write('playCount: $playCount, ')
          ..write('completeCount: $completeCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('replayCount: $replayCount, ')
          ..write('favoriteCount: $favoriteCount, ')
          ..write('totalListenedMs: $totalListenedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    songId,
    playCount,
    completeCount,
    skipCount,
    replayCount,
    favoriteCount,
    totalListenedMs,
    lastPlayedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongStatsRow &&
          other.songId == this.songId &&
          other.playCount == this.playCount &&
          other.completeCount == this.completeCount &&
          other.skipCount == this.skipCount &&
          other.replayCount == this.replayCount &&
          other.favoriteCount == this.favoriteCount &&
          other.totalListenedMs == this.totalListenedMs &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class SongStatsCompanion extends UpdateCompanion<SongStatsRow> {
  final Value<String> songId;
  final Value<int> playCount;
  final Value<int> completeCount;
  final Value<int> skipCount;
  final Value<int> replayCount;
  final Value<int> favoriteCount;
  final Value<int> totalListenedMs;
  final Value<String?> lastPlayedAt;
  final Value<int> rowid;
  const SongStatsCompanion({
    this.songId = const Value.absent(),
    this.playCount = const Value.absent(),
    this.completeCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.replayCount = const Value.absent(),
    this.favoriteCount = const Value.absent(),
    this.totalListenedMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongStatsCompanion.insert({
    required String songId,
    this.playCount = const Value.absent(),
    this.completeCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.replayCount = const Value.absent(),
    this.favoriteCount = const Value.absent(),
    this.totalListenedMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : songId = Value(songId);
  static Insertable<SongStatsRow> custom({
    Expression<String>? songId,
    Expression<int>? playCount,
    Expression<int>? completeCount,
    Expression<int>? skipCount,
    Expression<int>? replayCount,
    Expression<int>? favoriteCount,
    Expression<int>? totalListenedMs,
    Expression<String>? lastPlayedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (playCount != null) 'play_count': playCount,
      if (completeCount != null) 'complete_count': completeCount,
      if (skipCount != null) 'skip_count': skipCount,
      if (replayCount != null) 'replay_count': replayCount,
      if (favoriteCount != null) 'favorite_count': favoriteCount,
      if (totalListenedMs != null) 'total_listened_ms': totalListenedMs,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongStatsCompanion copyWith({
    Value<String>? songId,
    Value<int>? playCount,
    Value<int>? completeCount,
    Value<int>? skipCount,
    Value<int>? replayCount,
    Value<int>? favoriteCount,
    Value<int>? totalListenedMs,
    Value<String?>? lastPlayedAt,
    Value<int>? rowid,
  }) {
    return SongStatsCompanion(
      songId: songId ?? this.songId,
      playCount: playCount ?? this.playCount,
      completeCount: completeCount ?? this.completeCount,
      skipCount: skipCount ?? this.skipCount,
      replayCount: replayCount ?? this.replayCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      totalListenedMs: totalListenedMs ?? this.totalListenedMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (completeCount.present) {
      map['complete_count'] = Variable<int>(completeCount.value);
    }
    if (skipCount.present) {
      map['skip_count'] = Variable<int>(skipCount.value);
    }
    if (replayCount.present) {
      map['replay_count'] = Variable<int>(replayCount.value);
    }
    if (favoriteCount.present) {
      map['favorite_count'] = Variable<int>(favoriteCount.value);
    }
    if (totalListenedMs.present) {
      map['total_listened_ms'] = Variable<int>(totalListenedMs.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<String>(lastPlayedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongStatsCompanion(')
          ..write('songId: $songId, ')
          ..write('playCount: $playCount, ')
          ..write('completeCount: $completeCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('replayCount: $replayCount, ')
          ..write('favoriteCount: $favoriteCount, ')
          ..write('totalListenedMs: $totalListenedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListeningEventsTable extends ListeningEvents
    with TableInfo<$ListeningEventsTable, ListeningEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListeningEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextMeta = const VerificationMeta(
    'context',
  );
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
    'context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _listenedMsMeta = const VerificationMeta(
    'listenedMs',
  );
  @override
  late final GeneratedColumn<int> listenedMs = GeneratedColumn<int>(
    'listened_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    eventType,
    context,
    positionMs,
    listenedMs,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'listening_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ListeningEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('context')) {
      context.handle(
        _contextMeta,
        this.context.isAcceptableOrUnknown(data['context']!, _contextMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('listened_ms')) {
      context.handle(
        _listenedMsMeta,
        listenedMs.isAcceptableOrUnknown(data['listened_ms']!, _listenedMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ListeningEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListeningEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      context: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      ),
      listenedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}listened_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ListeningEventsTable createAlias(String alias) {
    return $ListeningEventsTable(attachedDatabase, alias);
  }
}

class ListeningEventRow extends DataClass
    implements Insertable<ListeningEventRow> {
  final int id;
  final String songId;
  final String eventType;
  final String? context;
  final int? positionMs;
  final int? listenedMs;
  final String createdAt;
  const ListeningEventRow({
    required this.id,
    required this.songId,
    required this.eventType,
    this.context,
    this.positionMs,
    this.listenedMs,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<String>(songId);
    map['event_type'] = Variable<String>(eventType);
    if (!nullToAbsent || context != null) {
      map['context'] = Variable<String>(context);
    }
    if (!nullToAbsent || positionMs != null) {
      map['position_ms'] = Variable<int>(positionMs);
    }
    if (!nullToAbsent || listenedMs != null) {
      map['listened_ms'] = Variable<int>(listenedMs);
    }
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  ListeningEventsCompanion toCompanion(bool nullToAbsent) {
    return ListeningEventsCompanion(
      id: Value(id),
      songId: Value(songId),
      eventType: Value(eventType),
      context: context == null && nullToAbsent
          ? const Value.absent()
          : Value(context),
      positionMs: positionMs == null && nullToAbsent
          ? const Value.absent()
          : Value(positionMs),
      listenedMs: listenedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(listenedMs),
      createdAt: Value(createdAt),
    );
  }

  factory ListeningEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListeningEventRow(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      context: serializer.fromJson<String?>(json['context']),
      positionMs: serializer.fromJson<int?>(json['positionMs']),
      listenedMs: serializer.fromJson<int?>(json['listenedMs']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<String>(songId),
      'eventType': serializer.toJson<String>(eventType),
      'context': serializer.toJson<String?>(context),
      'positionMs': serializer.toJson<int?>(positionMs),
      'listenedMs': serializer.toJson<int?>(listenedMs),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  ListeningEventRow copyWith({
    int? id,
    String? songId,
    String? eventType,
    Value<String?> context = const Value.absent(),
    Value<int?> positionMs = const Value.absent(),
    Value<int?> listenedMs = const Value.absent(),
    String? createdAt,
  }) => ListeningEventRow(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    eventType: eventType ?? this.eventType,
    context: context.present ? context.value : this.context,
    positionMs: positionMs.present ? positionMs.value : this.positionMs,
    listenedMs: listenedMs.present ? listenedMs.value : this.listenedMs,
    createdAt: createdAt ?? this.createdAt,
  );
  ListeningEventRow copyWithCompanion(ListeningEventsCompanion data) {
    return ListeningEventRow(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      context: data.context.present ? data.context.value : this.context,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      listenedMs: data.listenedMs.present
          ? data.listenedMs.value
          : this.listenedMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListeningEventRow(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('eventType: $eventType, ')
          ..write('context: $context, ')
          ..write('positionMs: $positionMs, ')
          ..write('listenedMs: $listenedMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    songId,
    eventType,
    context,
    positionMs,
    listenedMs,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListeningEventRow &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.eventType == this.eventType &&
          other.context == this.context &&
          other.positionMs == this.positionMs &&
          other.listenedMs == this.listenedMs &&
          other.createdAt == this.createdAt);
}

class ListeningEventsCompanion extends UpdateCompanion<ListeningEventRow> {
  final Value<int> id;
  final Value<String> songId;
  final Value<String> eventType;
  final Value<String?> context;
  final Value<int?> positionMs;
  final Value<int?> listenedMs;
  final Value<String> createdAt;
  const ListeningEventsCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.context = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.listenedMs = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ListeningEventsCompanion.insert({
    this.id = const Value.absent(),
    required String songId,
    required String eventType,
    this.context = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.listenedMs = const Value.absent(),
    required String createdAt,
  }) : songId = Value(songId),
       eventType = Value(eventType),
       createdAt = Value(createdAt);
  static Insertable<ListeningEventRow> custom({
    Expression<int>? id,
    Expression<String>? songId,
    Expression<String>? eventType,
    Expression<String>? context,
    Expression<int>? positionMs,
    Expression<int>? listenedMs,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (eventType != null) 'event_type': eventType,
      if (context != null) 'context': context,
      if (positionMs != null) 'position_ms': positionMs,
      if (listenedMs != null) 'listened_ms': listenedMs,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ListeningEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? songId,
    Value<String>? eventType,
    Value<String?>? context,
    Value<int?>? positionMs,
    Value<int?>? listenedMs,
    Value<String>? createdAt,
  }) {
    return ListeningEventsCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      eventType: eventType ?? this.eventType,
      context: context ?? this.context,
      positionMs: positionMs ?? this.positionMs,
      listenedMs: listenedMs ?? this.listenedMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (listenedMs.present) {
      map['listened_ms'] = Variable<int>(listenedMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListeningEventsCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('eventType: $eventType, ')
          ..write('context: $context, ')
          ..write('positionMs: $positionMs, ')
          ..write('listenedMs: $listenedMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ContextStatsTable extends ContextStats
    with TableInfo<$ContextStatsTable, ContextStatsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContextStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextMeta = const VerificationMeta(
    'context',
  );
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
    'context',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completeCountMeta = const VerificationMeta(
    'completeCount',
  );
  @override
  late final GeneratedColumn<int> completeCount = GeneratedColumn<int>(
    'complete_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skipCountMeta = const VerificationMeta(
    'skipCount',
  );
  @override
  late final GeneratedColumn<int> skipCount = GeneratedColumn<int>(
    'skip_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalListenedMsMeta = const VerificationMeta(
    'totalListenedMs',
  );
  @override
  late final GeneratedColumn<int> totalListenedMs = GeneratedColumn<int>(
    'total_listened_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    context,
    playCount,
    completeCount,
    skipCount,
    totalListenedMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'context_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContextStatsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('context')) {
      context.handle(
        _contextMeta,
        this.context.isAcceptableOrUnknown(data['context']!, _contextMeta),
      );
    } else if (isInserting) {
      context.missing(_contextMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('complete_count')) {
      context.handle(
        _completeCountMeta,
        completeCount.isAcceptableOrUnknown(
          data['complete_count']!,
          _completeCountMeta,
        ),
      );
    }
    if (data.containsKey('skip_count')) {
      context.handle(
        _skipCountMeta,
        skipCount.isAcceptableOrUnknown(data['skip_count']!, _skipCountMeta),
      );
    }
    if (data.containsKey('total_listened_ms')) {
      context.handle(
        _totalListenedMsMeta,
        totalListenedMs.isAcceptableOrUnknown(
          data['total_listened_ms']!,
          _totalListenedMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContextStatsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContextStatsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      context: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      completeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}complete_count'],
      )!,
      skipCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skip_count'],
      )!,
      totalListenedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_listened_ms'],
      )!,
    );
  }

  @override
  $ContextStatsTable createAlias(String alias) {
    return $ContextStatsTable(attachedDatabase, alias);
  }
}

class ContextStatsRow extends DataClass implements Insertable<ContextStatsRow> {
  final int id;
  final String songId;
  final String context;
  final int playCount;
  final int completeCount;
  final int skipCount;
  final int totalListenedMs;
  const ContextStatsRow({
    required this.id,
    required this.songId,
    required this.context,
    required this.playCount,
    required this.completeCount,
    required this.skipCount,
    required this.totalListenedMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<String>(songId);
    map['context'] = Variable<String>(context);
    map['play_count'] = Variable<int>(playCount);
    map['complete_count'] = Variable<int>(completeCount);
    map['skip_count'] = Variable<int>(skipCount);
    map['total_listened_ms'] = Variable<int>(totalListenedMs);
    return map;
  }

  ContextStatsCompanion toCompanion(bool nullToAbsent) {
    return ContextStatsCompanion(
      id: Value(id),
      songId: Value(songId),
      context: Value(context),
      playCount: Value(playCount),
      completeCount: Value(completeCount),
      skipCount: Value(skipCount),
      totalListenedMs: Value(totalListenedMs),
    );
  }

  factory ContextStatsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContextStatsRow(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      context: serializer.fromJson<String>(json['context']),
      playCount: serializer.fromJson<int>(json['playCount']),
      completeCount: serializer.fromJson<int>(json['completeCount']),
      skipCount: serializer.fromJson<int>(json['skipCount']),
      totalListenedMs: serializer.fromJson<int>(json['totalListenedMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<String>(songId),
      'context': serializer.toJson<String>(context),
      'playCount': serializer.toJson<int>(playCount),
      'completeCount': serializer.toJson<int>(completeCount),
      'skipCount': serializer.toJson<int>(skipCount),
      'totalListenedMs': serializer.toJson<int>(totalListenedMs),
    };
  }

  ContextStatsRow copyWith({
    int? id,
    String? songId,
    String? context,
    int? playCount,
    int? completeCount,
    int? skipCount,
    int? totalListenedMs,
  }) => ContextStatsRow(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    context: context ?? this.context,
    playCount: playCount ?? this.playCount,
    completeCount: completeCount ?? this.completeCount,
    skipCount: skipCount ?? this.skipCount,
    totalListenedMs: totalListenedMs ?? this.totalListenedMs,
  );
  ContextStatsRow copyWithCompanion(ContextStatsCompanion data) {
    return ContextStatsRow(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      context: data.context.present ? data.context.value : this.context,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      completeCount: data.completeCount.present
          ? data.completeCount.value
          : this.completeCount,
      skipCount: data.skipCount.present ? data.skipCount.value : this.skipCount,
      totalListenedMs: data.totalListenedMs.present
          ? data.totalListenedMs.value
          : this.totalListenedMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContextStatsRow(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('context: $context, ')
          ..write('playCount: $playCount, ')
          ..write('completeCount: $completeCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('totalListenedMs: $totalListenedMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    songId,
    context,
    playCount,
    completeCount,
    skipCount,
    totalListenedMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContextStatsRow &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.context == this.context &&
          other.playCount == this.playCount &&
          other.completeCount == this.completeCount &&
          other.skipCount == this.skipCount &&
          other.totalListenedMs == this.totalListenedMs);
}

class ContextStatsCompanion extends UpdateCompanion<ContextStatsRow> {
  final Value<int> id;
  final Value<String> songId;
  final Value<String> context;
  final Value<int> playCount;
  final Value<int> completeCount;
  final Value<int> skipCount;
  final Value<int> totalListenedMs;
  const ContextStatsCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.context = const Value.absent(),
    this.playCount = const Value.absent(),
    this.completeCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.totalListenedMs = const Value.absent(),
  });
  ContextStatsCompanion.insert({
    this.id = const Value.absent(),
    required String songId,
    required String context,
    this.playCount = const Value.absent(),
    this.completeCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.totalListenedMs = const Value.absent(),
  }) : songId = Value(songId),
       context = Value(context);
  static Insertable<ContextStatsRow> custom({
    Expression<int>? id,
    Expression<String>? songId,
    Expression<String>? context,
    Expression<int>? playCount,
    Expression<int>? completeCount,
    Expression<int>? skipCount,
    Expression<int>? totalListenedMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (context != null) 'context': context,
      if (playCount != null) 'play_count': playCount,
      if (completeCount != null) 'complete_count': completeCount,
      if (skipCount != null) 'skip_count': skipCount,
      if (totalListenedMs != null) 'total_listened_ms': totalListenedMs,
    });
  }

  ContextStatsCompanion copyWith({
    Value<int>? id,
    Value<String>? songId,
    Value<String>? context,
    Value<int>? playCount,
    Value<int>? completeCount,
    Value<int>? skipCount,
    Value<int>? totalListenedMs,
  }) {
    return ContextStatsCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      context: context ?? this.context,
      playCount: playCount ?? this.playCount,
      completeCount: completeCount ?? this.completeCount,
      skipCount: skipCount ?? this.skipCount,
      totalListenedMs: totalListenedMs ?? this.totalListenedMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (completeCount.present) {
      map['complete_count'] = Variable<int>(completeCount.value);
    }
    if (skipCount.present) {
      map['skip_count'] = Variable<int>(skipCount.value);
    }
    if (totalListenedMs.present) {
      map['total_listened_ms'] = Variable<int>(totalListenedMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContextStatsCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('context: $context, ')
          ..write('playCount: $playCount, ')
          ..write('completeCount: $completeCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('totalListenedMs: $totalListenedMs')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, PlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class PlaylistRow extends DataClass implements Insertable<PlaylistRow> {
  final String id;
  final String name;
  final String createdAt;
  const PlaylistRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory PlaylistRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  PlaylistRow copyWith({String? id, String? name, String? createdAt}) =>
      PlaylistRow(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
  PlaylistRow copyWithCompanion(PlaylistsCompanion data) {
    return PlaylistRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class PlaylistsCompanion extends UpdateCompanion<PlaylistRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> createdAt;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String name,
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<PlaylistRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistSongsTable extends PlaylistSongs
    with TableInfo<$PlaylistSongsTable, PlaylistSongRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistSongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [playlistId, songId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistSongRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId, songId};
  @override
  PlaylistSongRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistSongRow(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PlaylistSongsTable createAlias(String alias) {
    return $PlaylistSongsTable(attachedDatabase, alias);
  }
}

class PlaylistSongRow extends DataClass implements Insertable<PlaylistSongRow> {
  final String playlistId;
  final String songId;
  final int position;
  const PlaylistSongRow({
    required this.playlistId,
    required this.songId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['song_id'] = Variable<String>(songId);
    map['position'] = Variable<int>(position);
    return map;
  }

  PlaylistSongsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistSongsCompanion(
      playlistId: Value(playlistId),
      songId: Value(songId),
      position: Value(position),
    );
  }

  factory PlaylistSongRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistSongRow(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      songId: serializer.fromJson<String>(json['songId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'songId': serializer.toJson<String>(songId),
      'position': serializer.toJson<int>(position),
    };
  }

  PlaylistSongRow copyWith({
    String? playlistId,
    String? songId,
    int? position,
  }) => PlaylistSongRow(
    playlistId: playlistId ?? this.playlistId,
    songId: songId ?? this.songId,
    position: position ?? this.position,
  );
  PlaylistSongRow copyWithCompanion(PlaylistSongsCompanion data) {
    return PlaylistSongRow(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      songId: data.songId.present ? data.songId.value : this.songId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSongRow(')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistId, songId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistSongRow &&
          other.playlistId == this.playlistId &&
          other.songId == this.songId &&
          other.position == this.position);
}

class PlaylistSongsCompanion extends UpdateCompanion<PlaylistSongRow> {
  final Value<String> playlistId;
  final Value<String> songId;
  final Value<int> position;
  final Value<int> rowid;
  const PlaylistSongsCompanion({
    this.playlistId = const Value.absent(),
    this.songId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistSongsCompanion.insert({
    required String playlistId,
    required String songId,
    required int position,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       songId = Value(songId),
       position = Value(position);
  static Insertable<PlaylistSongRow> custom({
    Expression<String>? playlistId,
    Expression<String>? songId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (songId != null) 'song_id': songId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistSongsCompanion copyWith({
    Value<String>? playlistId,
    Value<String>? songId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return PlaylistSongsCompanion(
      playlistId: playlistId ?? this.playlistId,
      songId: songId ?? this.songId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSongsCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PronunciationFixesTable extends PronunciationFixes
    with TableInfo<$PronunciationFixesTable, PronunciationFixRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PronunciationFixesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _originalTextMeta = const VerificationMeta(
    'originalText',
  );
  @override
  late final GeneratedColumn<String> originalText = GeneratedColumn<String>(
    'original_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spokenTextMeta = const VerificationMeta(
    'spokenText',
  );
  @override
  late final GeneratedColumn<String> spokenText = GeneratedColumn<String>(
    'spoken_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('word'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    originalText,
    spokenText,
    type,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pronunciation_fixes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PronunciationFixRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('original_text')) {
      context.handle(
        _originalTextMeta,
        originalText.isAcceptableOrUnknown(
          data['original_text']!,
          _originalTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalTextMeta);
    }
    if (data.containsKey('spoken_text')) {
      context.handle(
        _spokenTextMeta,
        spokenText.isAcceptableOrUnknown(data['spoken_text']!, _spokenTextMeta),
      );
    } else if (isInserting) {
      context.missing(_spokenTextMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PronunciationFixRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PronunciationFixRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      originalText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_text'],
      )!,
      spokenText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spoken_text'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $PronunciationFixesTable createAlias(String alias) {
    return $PronunciationFixesTable(attachedDatabase, alias);
  }
}

class PronunciationFixRow extends DataClass
    implements Insertable<PronunciationFixRow> {
  final int id;
  final String originalText;
  final String spokenText;
  final String type;
  final String createdAt;
  final String? updatedAt;
  const PronunciationFixRow({
    required this.id,
    required this.originalText,
    required this.spokenText,
    required this.type,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['original_text'] = Variable<String>(originalText);
    map['spoken_text'] = Variable<String>(spokenText);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  PronunciationFixesCompanion toCompanion(bool nullToAbsent) {
    return PronunciationFixesCompanion(
      id: Value(id),
      originalText: Value(originalText),
      spokenText: Value(spokenText),
      type: Value(type),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory PronunciationFixRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PronunciationFixRow(
      id: serializer.fromJson<int>(json['id']),
      originalText: serializer.fromJson<String>(json['originalText']),
      spokenText: serializer.fromJson<String>(json['spokenText']),
      type: serializer.fromJson<String>(json['type']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'originalText': serializer.toJson<String>(originalText),
      'spokenText': serializer.toJson<String>(spokenText),
      'type': serializer.toJson<String>(type),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  PronunciationFixRow copyWith({
    int? id,
    String? originalText,
    String? spokenText,
    String? type,
    String? createdAt,
    Value<String?> updatedAt = const Value.absent(),
  }) => PronunciationFixRow(
    id: id ?? this.id,
    originalText: originalText ?? this.originalText,
    spokenText: spokenText ?? this.spokenText,
    type: type ?? this.type,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  PronunciationFixRow copyWithCompanion(PronunciationFixesCompanion data) {
    return PronunciationFixRow(
      id: data.id.present ? data.id.value : this.id,
      originalText: data.originalText.present
          ? data.originalText.value
          : this.originalText,
      spokenText: data.spokenText.present
          ? data.spokenText.value
          : this.spokenText,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PronunciationFixRow(')
          ..write('id: $id, ')
          ..write('originalText: $originalText, ')
          ..write('spokenText: $spokenText, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, originalText, spokenText, type, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PronunciationFixRow &&
          other.id == this.id &&
          other.originalText == this.originalText &&
          other.spokenText == this.spokenText &&
          other.type == this.type &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PronunciationFixesCompanion extends UpdateCompanion<PronunciationFixRow> {
  final Value<int> id;
  final Value<String> originalText;
  final Value<String> spokenText;
  final Value<String> type;
  final Value<String> createdAt;
  final Value<String?> updatedAt;
  const PronunciationFixesCompanion({
    this.id = const Value.absent(),
    this.originalText = const Value.absent(),
    this.spokenText = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PronunciationFixesCompanion.insert({
    this.id = const Value.absent(),
    required String originalText,
    required String spokenText,
    this.type = const Value.absent(),
    required String createdAt,
    this.updatedAt = const Value.absent(),
  }) : originalText = Value(originalText),
       spokenText = Value(spokenText),
       createdAt = Value(createdAt);
  static Insertable<PronunciationFixRow> custom({
    Expression<int>? id,
    Expression<String>? originalText,
    Expression<String>? spokenText,
    Expression<String>? type,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originalText != null) 'original_text': originalText,
      if (spokenText != null) 'spoken_text': spokenText,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PronunciationFixesCompanion copyWith({
    Value<int>? id,
    Value<String>? originalText,
    Value<String>? spokenText,
    Value<String>? type,
    Value<String>? createdAt,
    Value<String?>? updatedAt,
  }) {
    return PronunciationFixesCompanion(
      id: id ?? this.id,
      originalText: originalText ?? this.originalText,
      spokenText: spokenText ?? this.spokenText,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (originalText.present) {
      map['original_text'] = Variable<String>(originalText.value);
    }
    if (spokenText.present) {
      map['spoken_text'] = Variable<String>(spokenText.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PronunciationFixesCompanion(')
          ..write('id: $id, ')
          ..write('originalText: $originalText, ')
          ..write('spokenText: $spokenText, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $RecentDjLinesTable extends RecentDjLines
    with TableInfo<$RecentDjLinesTable, RecentDjLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentDjLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _lineTextMeta = const VerificationMeta(
    'lineText',
  );
  @override
  late final GeneratedColumn<String> lineText = GeneratedColumn<String>(
    'line_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intentMeta = const VerificationMeta('intent');
  @override
  late final GeneratedColumn<String> intent = GeneratedColumn<String>(
    'intent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lineText,
    intent,
    songId,
    mode,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_dj_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentDjLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('line_text')) {
      context.handle(
        _lineTextMeta,
        lineText.isAcceptableOrUnknown(data['line_text']!, _lineTextMeta),
      );
    } else if (isInserting) {
      context.missing(_lineTextMeta);
    }
    if (data.containsKey('intent')) {
      context.handle(
        _intentMeta,
        intent.isAcceptableOrUnknown(data['intent']!, _intentMeta),
      );
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentDjLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentDjLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lineText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_text'],
      )!,
      intent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent'],
      ),
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecentDjLinesTable createAlias(String alias) {
    return $RecentDjLinesTable(attachedDatabase, alias);
  }
}

class RecentDjLineRow extends DataClass implements Insertable<RecentDjLineRow> {
  final int id;
  final String lineText;
  final String? intent;
  final String? songId;
  final String? mode;
  final String createdAt;
  const RecentDjLineRow({
    required this.id,
    required this.lineText,
    this.intent,
    this.songId,
    this.mode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['line_text'] = Variable<String>(lineText);
    if (!nullToAbsent || intent != null) {
      map['intent'] = Variable<String>(intent);
    }
    if (!nullToAbsent || songId != null) {
      map['song_id'] = Variable<String>(songId);
    }
    if (!nullToAbsent || mode != null) {
      map['mode'] = Variable<String>(mode);
    }
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  RecentDjLinesCompanion toCompanion(bool nullToAbsent) {
    return RecentDjLinesCompanion(
      id: Value(id),
      lineText: Value(lineText),
      intent: intent == null && nullToAbsent
          ? const Value.absent()
          : Value(intent),
      songId: songId == null && nullToAbsent
          ? const Value.absent()
          : Value(songId),
      mode: mode == null && nullToAbsent ? const Value.absent() : Value(mode),
      createdAt: Value(createdAt),
    );
  }

  factory RecentDjLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentDjLineRow(
      id: serializer.fromJson<int>(json['id']),
      lineText: serializer.fromJson<String>(json['lineText']),
      intent: serializer.fromJson<String?>(json['intent']),
      songId: serializer.fromJson<String?>(json['songId']),
      mode: serializer.fromJson<String?>(json['mode']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lineText': serializer.toJson<String>(lineText),
      'intent': serializer.toJson<String?>(intent),
      'songId': serializer.toJson<String?>(songId),
      'mode': serializer.toJson<String?>(mode),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  RecentDjLineRow copyWith({
    int? id,
    String? lineText,
    Value<String?> intent = const Value.absent(),
    Value<String?> songId = const Value.absent(),
    Value<String?> mode = const Value.absent(),
    String? createdAt,
  }) => RecentDjLineRow(
    id: id ?? this.id,
    lineText: lineText ?? this.lineText,
    intent: intent.present ? intent.value : this.intent,
    songId: songId.present ? songId.value : this.songId,
    mode: mode.present ? mode.value : this.mode,
    createdAt: createdAt ?? this.createdAt,
  );
  RecentDjLineRow copyWithCompanion(RecentDjLinesCompanion data) {
    return RecentDjLineRow(
      id: data.id.present ? data.id.value : this.id,
      lineText: data.lineText.present ? data.lineText.value : this.lineText,
      intent: data.intent.present ? data.intent.value : this.intent,
      songId: data.songId.present ? data.songId.value : this.songId,
      mode: data.mode.present ? data.mode.value : this.mode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentDjLineRow(')
          ..write('id: $id, ')
          ..write('lineText: $lineText, ')
          ..write('intent: $intent, ')
          ..write('songId: $songId, ')
          ..write('mode: $mode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, lineText, intent, songId, mode, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentDjLineRow &&
          other.id == this.id &&
          other.lineText == this.lineText &&
          other.intent == this.intent &&
          other.songId == this.songId &&
          other.mode == this.mode &&
          other.createdAt == this.createdAt);
}

class RecentDjLinesCompanion extends UpdateCompanion<RecentDjLineRow> {
  final Value<int> id;
  final Value<String> lineText;
  final Value<String?> intent;
  final Value<String?> songId;
  final Value<String?> mode;
  final Value<String> createdAt;
  const RecentDjLinesCompanion({
    this.id = const Value.absent(),
    this.lineText = const Value.absent(),
    this.intent = const Value.absent(),
    this.songId = const Value.absent(),
    this.mode = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RecentDjLinesCompanion.insert({
    this.id = const Value.absent(),
    required String lineText,
    this.intent = const Value.absent(),
    this.songId = const Value.absent(),
    this.mode = const Value.absent(),
    required String createdAt,
  }) : lineText = Value(lineText),
       createdAt = Value(createdAt);
  static Insertable<RecentDjLineRow> custom({
    Expression<int>? id,
    Expression<String>? lineText,
    Expression<String>? intent,
    Expression<String>? songId,
    Expression<String>? mode,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lineText != null) 'line_text': lineText,
      if (intent != null) 'intent': intent,
      if (songId != null) 'song_id': songId,
      if (mode != null) 'mode': mode,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RecentDjLinesCompanion copyWith({
    Value<int>? id,
    Value<String>? lineText,
    Value<String?>? intent,
    Value<String?>? songId,
    Value<String?>? mode,
    Value<String>? createdAt,
  }) {
    return RecentDjLinesCompanion(
      id: id ?? this.id,
      lineText: lineText ?? this.lineText,
      intent: intent ?? this.intent,
      songId: songId ?? this.songId,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lineText.present) {
      map['line_text'] = Variable<String>(lineText.value);
    }
    if (intent.present) {
      map['intent'] = Variable<String>(intent.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentDjLinesCompanion(')
          ..write('id: $id, ')
          ..write('lineText: $lineText, ')
          ..write('intent: $intent, ')
          ..write('songId: $songId, ')
          ..write('mode: $mode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DjSpeechCacheTable extends DjSpeechCache
    with TableInfo<$DjSpeechCacheTable, DjSpeechCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DjSpeechCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intentMeta = const VerificationMeta('intent');
  @override
  late final GeneratedColumn<String> intent = GeneratedColumn<String>(
    'intent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queuePositionTypeMeta = const VerificationMeta(
    'queuePositionType',
  );
  @override
  late final GeneratedColumn<String> queuePositionType =
      GeneratedColumn<String>(
        'queue_position_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spokenTextMeta = const VerificationMeta(
    'spokenText',
  );
  @override
  late final GeneratedColumn<String> spokenText = GeneratedColumn<String>(
    'spoken_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voiceIdMeta = const VerificationMeta(
    'voiceId',
  );
  @override
  late final GeneratedColumn<String> voiceId = GeneratedColumn<String>(
    'voice_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    mode,
    intent,
    queuePositionType,
    rawText,
    spokenText,
    audioPath,
    voiceId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dj_speech_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<DjSpeechCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('intent')) {
      context.handle(
        _intentMeta,
        intent.isAcceptableOrUnknown(data['intent']!, _intentMeta),
      );
    } else if (isInserting) {
      context.missing(_intentMeta);
    }
    if (data.containsKey('queue_position_type')) {
      context.handle(
        _queuePositionTypeMeta,
        queuePositionType.isAcceptableOrUnknown(
          data['queue_position_type']!,
          _queuePositionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_queuePositionTypeMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('spoken_text')) {
      context.handle(
        _spokenTextMeta,
        spokenText.isAcceptableOrUnknown(data['spoken_text']!, _spokenTextMeta),
      );
    } else if (isInserting) {
      context.missing(_spokenTextMeta);
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('voice_id')) {
      context.handle(
        _voiceIdMeta,
        voiceId.isAcceptableOrUnknown(data['voice_id']!, _voiceIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DjSpeechCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DjSpeechCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      intent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent'],
      )!,
      queuePositionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_position_type'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      spokenText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spoken_text'],
      )!,
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      voiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $DjSpeechCacheTable createAlias(String alias) {
    return $DjSpeechCacheTable(attachedDatabase, alias);
  }
}

class DjSpeechCacheRow extends DataClass
    implements Insertable<DjSpeechCacheRow> {
  final String id;
  final String songId;
  final String mode;
  final String intent;
  final String queuePositionType;
  final String rawText;
  final String spokenText;
  final String? audioPath;
  final String? voiceId;
  final String createdAt;
  final String? updatedAt;
  const DjSpeechCacheRow({
    required this.id,
    required this.songId,
    required this.mode,
    required this.intent,
    required this.queuePositionType,
    required this.rawText,
    required this.spokenText,
    this.audioPath,
    this.voiceId,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['song_id'] = Variable<String>(songId);
    map['mode'] = Variable<String>(mode);
    map['intent'] = Variable<String>(intent);
    map['queue_position_type'] = Variable<String>(queuePositionType);
    map['raw_text'] = Variable<String>(rawText);
    map['spoken_text'] = Variable<String>(spokenText);
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    if (!nullToAbsent || voiceId != null) {
      map['voice_id'] = Variable<String>(voiceId);
    }
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  DjSpeechCacheCompanion toCompanion(bool nullToAbsent) {
    return DjSpeechCacheCompanion(
      id: Value(id),
      songId: Value(songId),
      mode: Value(mode),
      intent: Value(intent),
      queuePositionType: Value(queuePositionType),
      rawText: Value(rawText),
      spokenText: Value(spokenText),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      voiceId: voiceId == null && nullToAbsent
          ? const Value.absent()
          : Value(voiceId),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory DjSpeechCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DjSpeechCacheRow(
      id: serializer.fromJson<String>(json['id']),
      songId: serializer.fromJson<String>(json['songId']),
      mode: serializer.fromJson<String>(json['mode']),
      intent: serializer.fromJson<String>(json['intent']),
      queuePositionType: serializer.fromJson<String>(json['queuePositionType']),
      rawText: serializer.fromJson<String>(json['rawText']),
      spokenText: serializer.fromJson<String>(json['spokenText']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      voiceId: serializer.fromJson<String?>(json['voiceId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'songId': serializer.toJson<String>(songId),
      'mode': serializer.toJson<String>(mode),
      'intent': serializer.toJson<String>(intent),
      'queuePositionType': serializer.toJson<String>(queuePositionType),
      'rawText': serializer.toJson<String>(rawText),
      'spokenText': serializer.toJson<String>(spokenText),
      'audioPath': serializer.toJson<String?>(audioPath),
      'voiceId': serializer.toJson<String?>(voiceId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  DjSpeechCacheRow copyWith({
    String? id,
    String? songId,
    String? mode,
    String? intent,
    String? queuePositionType,
    String? rawText,
    String? spokenText,
    Value<String?> audioPath = const Value.absent(),
    Value<String?> voiceId = const Value.absent(),
    String? createdAt,
    Value<String?> updatedAt = const Value.absent(),
  }) => DjSpeechCacheRow(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    mode: mode ?? this.mode,
    intent: intent ?? this.intent,
    queuePositionType: queuePositionType ?? this.queuePositionType,
    rawText: rawText ?? this.rawText,
    spokenText: spokenText ?? this.spokenText,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    voiceId: voiceId.present ? voiceId.value : this.voiceId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  DjSpeechCacheRow copyWithCompanion(DjSpeechCacheCompanion data) {
    return DjSpeechCacheRow(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      mode: data.mode.present ? data.mode.value : this.mode,
      intent: data.intent.present ? data.intent.value : this.intent,
      queuePositionType: data.queuePositionType.present
          ? data.queuePositionType.value
          : this.queuePositionType,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      spokenText: data.spokenText.present
          ? data.spokenText.value
          : this.spokenText,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      voiceId: data.voiceId.present ? data.voiceId.value : this.voiceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DjSpeechCacheRow(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('mode: $mode, ')
          ..write('intent: $intent, ')
          ..write('queuePositionType: $queuePositionType, ')
          ..write('rawText: $rawText, ')
          ..write('spokenText: $spokenText, ')
          ..write('audioPath: $audioPath, ')
          ..write('voiceId: $voiceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    songId,
    mode,
    intent,
    queuePositionType,
    rawText,
    spokenText,
    audioPath,
    voiceId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DjSpeechCacheRow &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.mode == this.mode &&
          other.intent == this.intent &&
          other.queuePositionType == this.queuePositionType &&
          other.rawText == this.rawText &&
          other.spokenText == this.spokenText &&
          other.audioPath == this.audioPath &&
          other.voiceId == this.voiceId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DjSpeechCacheCompanion extends UpdateCompanion<DjSpeechCacheRow> {
  final Value<String> id;
  final Value<String> songId;
  final Value<String> mode;
  final Value<String> intent;
  final Value<String> queuePositionType;
  final Value<String> rawText;
  final Value<String> spokenText;
  final Value<String?> audioPath;
  final Value<String?> voiceId;
  final Value<String> createdAt;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const DjSpeechCacheCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.mode = const Value.absent(),
    this.intent = const Value.absent(),
    this.queuePositionType = const Value.absent(),
    this.rawText = const Value.absent(),
    this.spokenText = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.voiceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DjSpeechCacheCompanion.insert({
    required String id,
    required String songId,
    required String mode,
    required String intent,
    required String queuePositionType,
    required String rawText,
    required String spokenText,
    this.audioPath = const Value.absent(),
    this.voiceId = const Value.absent(),
    required String createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       songId = Value(songId),
       mode = Value(mode),
       intent = Value(intent),
       queuePositionType = Value(queuePositionType),
       rawText = Value(rawText),
       spokenText = Value(spokenText),
       createdAt = Value(createdAt);
  static Insertable<DjSpeechCacheRow> custom({
    Expression<String>? id,
    Expression<String>? songId,
    Expression<String>? mode,
    Expression<String>? intent,
    Expression<String>? queuePositionType,
    Expression<String>? rawText,
    Expression<String>? spokenText,
    Expression<String>? audioPath,
    Expression<String>? voiceId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (mode != null) 'mode': mode,
      if (intent != null) 'intent': intent,
      if (queuePositionType != null) 'queue_position_type': queuePositionType,
      if (rawText != null) 'raw_text': rawText,
      if (spokenText != null) 'spoken_text': spokenText,
      if (audioPath != null) 'audio_path': audioPath,
      if (voiceId != null) 'voice_id': voiceId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DjSpeechCacheCompanion copyWith({
    Value<String>? id,
    Value<String>? songId,
    Value<String>? mode,
    Value<String>? intent,
    Value<String>? queuePositionType,
    Value<String>? rawText,
    Value<String>? spokenText,
    Value<String?>? audioPath,
    Value<String?>? voiceId,
    Value<String>? createdAt,
    Value<String?>? updatedAt,
    Value<int>? rowid,
  }) {
    return DjSpeechCacheCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      mode: mode ?? this.mode,
      intent: intent ?? this.intent,
      queuePositionType: queuePositionType ?? this.queuePositionType,
      rawText: rawText ?? this.rawText,
      spokenText: spokenText ?? this.spokenText,
      audioPath: audioPath ?? this.audioPath,
      voiceId: voiceId ?? this.voiceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (intent.present) {
      map['intent'] = Variable<String>(intent.value);
    }
    if (queuePositionType.present) {
      map['queue_position_type'] = Variable<String>(queuePositionType.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (spokenText.present) {
      map['spoken_text'] = Variable<String>(spokenText.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (voiceId.present) {
      map['voice_id'] = Variable<String>(voiceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DjSpeechCacheCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('mode: $mode, ')
          ..write('intent: $intent, ')
          ..write('queuePositionType: $queuePositionType, ')
          ..write('rawText: $rawText, ')
          ..write('spokenText: $spokenText, ')
          ..write('audioPath: $audioPath, ')
          ..write('voiceId: $voiceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $SongStatsTable songStats = $SongStatsTable(this);
  late final $ListeningEventsTable listeningEvents = $ListeningEventsTable(
    this,
  );
  late final $ContextStatsTable contextStats = $ContextStatsTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistSongsTable playlistSongs = $PlaylistSongsTable(this);
  late final $PronunciationFixesTable pronunciationFixes =
      $PronunciationFixesTable(this);
  late final $RecentDjLinesTable recentDjLines = $RecentDjLinesTable(this);
  late final $DjSpeechCacheTable djSpeechCache = $DjSpeechCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    songs,
    songStats,
    listeningEvents,
    contextStats,
    playlists,
    playlistSongs,
    pronunciationFixes,
    recentDjLines,
    djSpeechCache,
  ];
}

typedef $$SongsTableCreateCompanionBuilder =
    SongsCompanion Function({
      required String id,
      required String title,
      Value<String?> artist,
      Value<String?> album,
      Value<String?> genre,
      Value<String?> mood,
      Value<int?> bpm,
      Value<int?> durationMs,
      Value<String?> fileName,
      required String localFilePath,
      Value<String?> localLyricsPath,
      Value<String?> localArtworkPath,
      Value<String?> searchText,
      Value<String?> addedAt,
      Value<String?> lastPlayedAt,
      Value<int> isFavorite,
      Value<int> rowid,
    });
typedef $$SongsTableUpdateCompanionBuilder =
    SongsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> artist,
      Value<String?> album,
      Value<String?> genre,
      Value<String?> mood,
      Value<int?> bpm,
      Value<int?> durationMs,
      Value<String?> fileName,
      Value<String> localFilePath,
      Value<String?> localLyricsPath,
      Value<String?> localArtworkPath,
      Value<String?> searchText,
      Value<String?> addedAt,
      Value<String?> lastPlayedAt,
      Value<int> isFavorite,
      Value<int> rowid,
    });

class $$SongsTableFilterComposer extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localLyricsPath => $composableBuilder(
    column: $table.localLyricsPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localArtworkPath => $composableBuilder(
    column: $table.localArtworkPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localLyricsPath => $composableBuilder(
    column: $table.localLyricsPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localArtworkPath => $composableBuilder(
    column: $table.localArtworkPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<int> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localLyricsPath => $composableBuilder(
    column: $table.localLyricsPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localArtworkPath => $composableBuilder(
    column: $table.localArtworkPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongsTable,
          SongRow,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (SongRow, BaseReferences<_$AppDatabase, $SongsTable, SongRow>),
          SongRow,
          PrefetchHooks Function()
        > {
  $$SongsTableTableManager(_$AppDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<int?> bpm = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<String?> localLyricsPath = const Value.absent(),
                Value<String?> localArtworkPath = const Value.absent(),
                Value<String?> searchText = const Value.absent(),
                Value<String?> addedAt = const Value.absent(),
                Value<String?> lastPlayedAt = const Value.absent(),
                Value<int> isFavorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                mood: mood,
                bpm: bpm,
                durationMs: durationMs,
                fileName: fileName,
                localFilePath: localFilePath,
                localLyricsPath: localLyricsPath,
                localArtworkPath: localArtworkPath,
                searchText: searchText,
                addedAt: addedAt,
                lastPlayedAt: lastPlayedAt,
                isFavorite: isFavorite,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<int?> bpm = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                required String localFilePath,
                Value<String?> localLyricsPath = const Value.absent(),
                Value<String?> localArtworkPath = const Value.absent(),
                Value<String?> searchText = const Value.absent(),
                Value<String?> addedAt = const Value.absent(),
                Value<String?> lastPlayedAt = const Value.absent(),
                Value<int> isFavorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                mood: mood,
                bpm: bpm,
                durationMs: durationMs,
                fileName: fileName,
                localFilePath: localFilePath,
                localLyricsPath: localLyricsPath,
                localArtworkPath: localArtworkPath,
                searchText: searchText,
                addedAt: addedAt,
                lastPlayedAt: lastPlayedAt,
                isFavorite: isFavorite,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongsTable,
      SongRow,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (SongRow, BaseReferences<_$AppDatabase, $SongsTable, SongRow>),
      SongRow,
      PrefetchHooks Function()
    >;
typedef $$SongStatsTableCreateCompanionBuilder =
    SongStatsCompanion Function({
      required String songId,
      Value<int> playCount,
      Value<int> completeCount,
      Value<int> skipCount,
      Value<int> replayCount,
      Value<int> favoriteCount,
      Value<int> totalListenedMs,
      Value<String?> lastPlayedAt,
      Value<int> rowid,
    });
typedef $$SongStatsTableUpdateCompanionBuilder =
    SongStatsCompanion Function({
      Value<String> songId,
      Value<int> playCount,
      Value<int> completeCount,
      Value<int> skipCount,
      Value<int> replayCount,
      Value<int> favoriteCount,
      Value<int> totalListenedMs,
      Value<String?> lastPlayedAt,
      Value<int> rowid,
    });

class $$SongStatsTableFilterComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skipCount => $composableBuilder(
    column: $table.skipCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get replayCount => $composableBuilder(
    column: $table.replayCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favoriteCount => $composableBuilder(
    column: $table.favoriteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skipCount => $composableBuilder(
    column: $table.skipCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get replayCount => $composableBuilder(
    column: $table.replayCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favoriteCount => $composableBuilder(
    column: $table.favoriteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get skipCount =>
      $composableBuilder(column: $table.skipCount, builder: (column) => column);

  GeneratedColumn<int> get replayCount => $composableBuilder(
    column: $table.replayCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get favoriteCount => $composableBuilder(
    column: $table.favoriteCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );
}

class $$SongStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongStatsTable,
          SongStatsRow,
          $$SongStatsTableFilterComposer,
          $$SongStatsTableOrderingComposer,
          $$SongStatsTableAnnotationComposer,
          $$SongStatsTableCreateCompanionBuilder,
          $$SongStatsTableUpdateCompanionBuilder,
          (
            SongStatsRow,
            BaseReferences<_$AppDatabase, $SongStatsTable, SongStatsRow>,
          ),
          SongStatsRow,
          PrefetchHooks Function()
        > {
  $$SongStatsTableTableManager(_$AppDatabase db, $SongStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> songId = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> completeCount = const Value.absent(),
                Value<int> skipCount = const Value.absent(),
                Value<int> replayCount = const Value.absent(),
                Value<int> favoriteCount = const Value.absent(),
                Value<int> totalListenedMs = const Value.absent(),
                Value<String?> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongStatsCompanion(
                songId: songId,
                playCount: playCount,
                completeCount: completeCount,
                skipCount: skipCount,
                replayCount: replayCount,
                favoriteCount: favoriteCount,
                totalListenedMs: totalListenedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String songId,
                Value<int> playCount = const Value.absent(),
                Value<int> completeCount = const Value.absent(),
                Value<int> skipCount = const Value.absent(),
                Value<int> replayCount = const Value.absent(),
                Value<int> favoriteCount = const Value.absent(),
                Value<int> totalListenedMs = const Value.absent(),
                Value<String?> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongStatsCompanion.insert(
                songId: songId,
                playCount: playCount,
                completeCount: completeCount,
                skipCount: skipCount,
                replayCount: replayCount,
                favoriteCount: favoriteCount,
                totalListenedMs: totalListenedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongStatsTable,
      SongStatsRow,
      $$SongStatsTableFilterComposer,
      $$SongStatsTableOrderingComposer,
      $$SongStatsTableAnnotationComposer,
      $$SongStatsTableCreateCompanionBuilder,
      $$SongStatsTableUpdateCompanionBuilder,
      (
        SongStatsRow,
        BaseReferences<_$AppDatabase, $SongStatsTable, SongStatsRow>,
      ),
      SongStatsRow,
      PrefetchHooks Function()
    >;
typedef $$ListeningEventsTableCreateCompanionBuilder =
    ListeningEventsCompanion Function({
      Value<int> id,
      required String songId,
      required String eventType,
      Value<String?> context,
      Value<int?> positionMs,
      Value<int?> listenedMs,
      required String createdAt,
    });
typedef $$ListeningEventsTableUpdateCompanionBuilder =
    ListeningEventsCompanion Function({
      Value<int> id,
      Value<String> songId,
      Value<String> eventType,
      Value<String?> context,
      Value<int?> positionMs,
      Value<int?> listenedMs,
      Value<String> createdAt,
    });

class $$ListeningEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ListeningEventsTable> {
  $$ListeningEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get listenedMs => $composableBuilder(
    column: $table.listenedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ListeningEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ListeningEventsTable> {
  $$ListeningEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get listenedMs => $composableBuilder(
    column: $table.listenedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ListeningEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ListeningEventsTable> {
  $$ListeningEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get context =>
      $composableBuilder(column: $table.context, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get listenedMs => $composableBuilder(
    column: $table.listenedMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ListeningEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ListeningEventsTable,
          ListeningEventRow,
          $$ListeningEventsTableFilterComposer,
          $$ListeningEventsTableOrderingComposer,
          $$ListeningEventsTableAnnotationComposer,
          $$ListeningEventsTableCreateCompanionBuilder,
          $$ListeningEventsTableUpdateCompanionBuilder,
          (
            ListeningEventRow,
            BaseReferences<
              _$AppDatabase,
              $ListeningEventsTable,
              ListeningEventRow
            >,
          ),
          ListeningEventRow,
          PrefetchHooks Function()
        > {
  $$ListeningEventsTableTableManager(
    _$AppDatabase db,
    $ListeningEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListeningEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListeningEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListeningEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String?> context = const Value.absent(),
                Value<int?> positionMs = const Value.absent(),
                Value<int?> listenedMs = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => ListeningEventsCompanion(
                id: id,
                songId: songId,
                eventType: eventType,
                context: context,
                positionMs: positionMs,
                listenedMs: listenedMs,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String songId,
                required String eventType,
                Value<String?> context = const Value.absent(),
                Value<int?> positionMs = const Value.absent(),
                Value<int?> listenedMs = const Value.absent(),
                required String createdAt,
              }) => ListeningEventsCompanion.insert(
                id: id,
                songId: songId,
                eventType: eventType,
                context: context,
                positionMs: positionMs,
                listenedMs: listenedMs,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ListeningEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ListeningEventsTable,
      ListeningEventRow,
      $$ListeningEventsTableFilterComposer,
      $$ListeningEventsTableOrderingComposer,
      $$ListeningEventsTableAnnotationComposer,
      $$ListeningEventsTableCreateCompanionBuilder,
      $$ListeningEventsTableUpdateCompanionBuilder,
      (
        ListeningEventRow,
        BaseReferences<_$AppDatabase, $ListeningEventsTable, ListeningEventRow>,
      ),
      ListeningEventRow,
      PrefetchHooks Function()
    >;
typedef $$ContextStatsTableCreateCompanionBuilder =
    ContextStatsCompanion Function({
      Value<int> id,
      required String songId,
      required String context,
      Value<int> playCount,
      Value<int> completeCount,
      Value<int> skipCount,
      Value<int> totalListenedMs,
    });
typedef $$ContextStatsTableUpdateCompanionBuilder =
    ContextStatsCompanion Function({
      Value<int> id,
      Value<String> songId,
      Value<String> context,
      Value<int> playCount,
      Value<int> completeCount,
      Value<int> skipCount,
      Value<int> totalListenedMs,
    });

class $$ContextStatsTableFilterComposer
    extends Composer<_$AppDatabase, $ContextStatsTable> {
  $$ContextStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skipCount => $composableBuilder(
    column: $table.skipCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContextStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContextStatsTable> {
  $$ContextStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skipCount => $composableBuilder(
    column: $table.skipCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContextStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContextStatsTable> {
  $$ContextStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get context =>
      $composableBuilder(column: $table.context, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get completeCount => $composableBuilder(
    column: $table.completeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get skipCount =>
      $composableBuilder(column: $table.skipCount, builder: (column) => column);

  GeneratedColumn<int> get totalListenedMs => $composableBuilder(
    column: $table.totalListenedMs,
    builder: (column) => column,
  );
}

class $$ContextStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContextStatsTable,
          ContextStatsRow,
          $$ContextStatsTableFilterComposer,
          $$ContextStatsTableOrderingComposer,
          $$ContextStatsTableAnnotationComposer,
          $$ContextStatsTableCreateCompanionBuilder,
          $$ContextStatsTableUpdateCompanionBuilder,
          (
            ContextStatsRow,
            BaseReferences<_$AppDatabase, $ContextStatsTable, ContextStatsRow>,
          ),
          ContextStatsRow,
          PrefetchHooks Function()
        > {
  $$ContextStatsTableTableManager(_$AppDatabase db, $ContextStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContextStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContextStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContextStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> context = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> completeCount = const Value.absent(),
                Value<int> skipCount = const Value.absent(),
                Value<int> totalListenedMs = const Value.absent(),
              }) => ContextStatsCompanion(
                id: id,
                songId: songId,
                context: context,
                playCount: playCount,
                completeCount: completeCount,
                skipCount: skipCount,
                totalListenedMs: totalListenedMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String songId,
                required String context,
                Value<int> playCount = const Value.absent(),
                Value<int> completeCount = const Value.absent(),
                Value<int> skipCount = const Value.absent(),
                Value<int> totalListenedMs = const Value.absent(),
              }) => ContextStatsCompanion.insert(
                id: id,
                songId: songId,
                context: context,
                playCount: playCount,
                completeCount: completeCount,
                skipCount: skipCount,
                totalListenedMs: totalListenedMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContextStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContextStatsTable,
      ContextStatsRow,
      $$ContextStatsTableFilterComposer,
      $$ContextStatsTableOrderingComposer,
      $$ContextStatsTableAnnotationComposer,
      $$ContextStatsTableCreateCompanionBuilder,
      $$ContextStatsTableUpdateCompanionBuilder,
      (
        ContextStatsRow,
        BaseReferences<_$AppDatabase, $ContextStatsTable, ContextStatsRow>,
      ),
      ContextStatsRow,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder =
    PlaylistsCompanion Function({
      required String id,
      required String name,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$PlaylistsTableUpdateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          PlaylistRow,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (
            PlaylistRow,
            BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow>,
          ),
          PlaylistRow,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      PlaylistRow,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (
        PlaylistRow,
        BaseReferences<_$AppDatabase, $PlaylistsTable, PlaylistRow>,
      ),
      PlaylistRow,
      PrefetchHooks Function()
    >;
typedef $$PlaylistSongsTableCreateCompanionBuilder =
    PlaylistSongsCompanion Function({
      required String playlistId,
      required String songId,
      required int position,
      Value<int> rowid,
    });
typedef $$PlaylistSongsTableUpdateCompanionBuilder =
    PlaylistSongsCompanion Function({
      Value<String> playlistId,
      Value<String> songId,
      Value<int> position,
      Value<int> rowid,
    });

class $$PlaylistSongsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistSongsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistSongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$PlaylistSongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistSongsTable,
          PlaylistSongRow,
          $$PlaylistSongsTableFilterComposer,
          $$PlaylistSongsTableOrderingComposer,
          $$PlaylistSongsTableAnnotationComposer,
          $$PlaylistSongsTableCreateCompanionBuilder,
          $$PlaylistSongsTableUpdateCompanionBuilder,
          (
            PlaylistSongRow,
            BaseReferences<_$AppDatabase, $PlaylistSongsTable, PlaylistSongRow>,
          ),
          PlaylistSongRow,
          PrefetchHooks Function()
        > {
  $$PlaylistSongsTableTableManager(_$AppDatabase db, $PlaylistSongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistSongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistSongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistSongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistSongsCompanion(
                playlistId: playlistId,
                songId: songId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required String songId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistSongsCompanion.insert(
                playlistId: playlistId,
                songId: songId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistSongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistSongsTable,
      PlaylistSongRow,
      $$PlaylistSongsTableFilterComposer,
      $$PlaylistSongsTableOrderingComposer,
      $$PlaylistSongsTableAnnotationComposer,
      $$PlaylistSongsTableCreateCompanionBuilder,
      $$PlaylistSongsTableUpdateCompanionBuilder,
      (
        PlaylistSongRow,
        BaseReferences<_$AppDatabase, $PlaylistSongsTable, PlaylistSongRow>,
      ),
      PlaylistSongRow,
      PrefetchHooks Function()
    >;
typedef $$PronunciationFixesTableCreateCompanionBuilder =
    PronunciationFixesCompanion Function({
      Value<int> id,
      required String originalText,
      required String spokenText,
      Value<String> type,
      required String createdAt,
      Value<String?> updatedAt,
    });
typedef $$PronunciationFixesTableUpdateCompanionBuilder =
    PronunciationFixesCompanion Function({
      Value<int> id,
      Value<String> originalText,
      Value<String> spokenText,
      Value<String> type,
      Value<String> createdAt,
      Value<String?> updatedAt,
    });

class $$PronunciationFixesTableFilterComposer
    extends Composer<_$AppDatabase, $PronunciationFixesTable> {
  $$PronunciationFixesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalText => $composableBuilder(
    column: $table.originalText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PronunciationFixesTableOrderingComposer
    extends Composer<_$AppDatabase, $PronunciationFixesTable> {
  $$PronunciationFixesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalText => $composableBuilder(
    column: $table.originalText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PronunciationFixesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PronunciationFixesTable> {
  $$PronunciationFixesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalText => $composableBuilder(
    column: $table.originalText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PronunciationFixesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PronunciationFixesTable,
          PronunciationFixRow,
          $$PronunciationFixesTableFilterComposer,
          $$PronunciationFixesTableOrderingComposer,
          $$PronunciationFixesTableAnnotationComposer,
          $$PronunciationFixesTableCreateCompanionBuilder,
          $$PronunciationFixesTableUpdateCompanionBuilder,
          (
            PronunciationFixRow,
            BaseReferences<
              _$AppDatabase,
              $PronunciationFixesTable,
              PronunciationFixRow
            >,
          ),
          PronunciationFixRow,
          PrefetchHooks Function()
        > {
  $$PronunciationFixesTableTableManager(
    _$AppDatabase db,
    $PronunciationFixesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PronunciationFixesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PronunciationFixesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PronunciationFixesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> originalText = const Value.absent(),
                Value<String> spokenText = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
              }) => PronunciationFixesCompanion(
                id: id,
                originalText: originalText,
                spokenText: spokenText,
                type: type,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String originalText,
                required String spokenText,
                Value<String> type = const Value.absent(),
                required String createdAt,
                Value<String?> updatedAt = const Value.absent(),
              }) => PronunciationFixesCompanion.insert(
                id: id,
                originalText: originalText,
                spokenText: spokenText,
                type: type,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PronunciationFixesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PronunciationFixesTable,
      PronunciationFixRow,
      $$PronunciationFixesTableFilterComposer,
      $$PronunciationFixesTableOrderingComposer,
      $$PronunciationFixesTableAnnotationComposer,
      $$PronunciationFixesTableCreateCompanionBuilder,
      $$PronunciationFixesTableUpdateCompanionBuilder,
      (
        PronunciationFixRow,
        BaseReferences<
          _$AppDatabase,
          $PronunciationFixesTable,
          PronunciationFixRow
        >,
      ),
      PronunciationFixRow,
      PrefetchHooks Function()
    >;
typedef $$RecentDjLinesTableCreateCompanionBuilder =
    RecentDjLinesCompanion Function({
      Value<int> id,
      required String lineText,
      Value<String?> intent,
      Value<String?> songId,
      Value<String?> mode,
      required String createdAt,
    });
typedef $$RecentDjLinesTableUpdateCompanionBuilder =
    RecentDjLinesCompanion Function({
      Value<int> id,
      Value<String> lineText,
      Value<String?> intent,
      Value<String?> songId,
      Value<String?> mode,
      Value<String> createdAt,
    });

class $$RecentDjLinesTableFilterComposer
    extends Composer<_$AppDatabase, $RecentDjLinesTable> {
  $$RecentDjLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineText => $composableBuilder(
    column: $table.lineText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentDjLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentDjLinesTable> {
  $$RecentDjLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineText => $composableBuilder(
    column: $table.lineText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentDjLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentDjLinesTable> {
  $$RecentDjLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lineText =>
      $composableBuilder(column: $table.lineText, builder: (column) => column);

  GeneratedColumn<String> get intent =>
      $composableBuilder(column: $table.intent, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RecentDjLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentDjLinesTable,
          RecentDjLineRow,
          $$RecentDjLinesTableFilterComposer,
          $$RecentDjLinesTableOrderingComposer,
          $$RecentDjLinesTableAnnotationComposer,
          $$RecentDjLinesTableCreateCompanionBuilder,
          $$RecentDjLinesTableUpdateCompanionBuilder,
          (
            RecentDjLineRow,
            BaseReferences<_$AppDatabase, $RecentDjLinesTable, RecentDjLineRow>,
          ),
          RecentDjLineRow,
          PrefetchHooks Function()
        > {
  $$RecentDjLinesTableTableManager(_$AppDatabase db, $RecentDjLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentDjLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentDjLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentDjLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> lineText = const Value.absent(),
                Value<String?> intent = const Value.absent(),
                Value<String?> songId = const Value.absent(),
                Value<String?> mode = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => RecentDjLinesCompanion(
                id: id,
                lineText: lineText,
                intent: intent,
                songId: songId,
                mode: mode,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String lineText,
                Value<String?> intent = const Value.absent(),
                Value<String?> songId = const Value.absent(),
                Value<String?> mode = const Value.absent(),
                required String createdAt,
              }) => RecentDjLinesCompanion.insert(
                id: id,
                lineText: lineText,
                intent: intent,
                songId: songId,
                mode: mode,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentDjLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentDjLinesTable,
      RecentDjLineRow,
      $$RecentDjLinesTableFilterComposer,
      $$RecentDjLinesTableOrderingComposer,
      $$RecentDjLinesTableAnnotationComposer,
      $$RecentDjLinesTableCreateCompanionBuilder,
      $$RecentDjLinesTableUpdateCompanionBuilder,
      (
        RecentDjLineRow,
        BaseReferences<_$AppDatabase, $RecentDjLinesTable, RecentDjLineRow>,
      ),
      RecentDjLineRow,
      PrefetchHooks Function()
    >;
typedef $$DjSpeechCacheTableCreateCompanionBuilder =
    DjSpeechCacheCompanion Function({
      required String id,
      required String songId,
      required String mode,
      required String intent,
      required String queuePositionType,
      required String rawText,
      required String spokenText,
      Value<String?> audioPath,
      Value<String?> voiceId,
      required String createdAt,
      Value<String?> updatedAt,
      Value<int> rowid,
    });
typedef $$DjSpeechCacheTableUpdateCompanionBuilder =
    DjSpeechCacheCompanion Function({
      Value<String> id,
      Value<String> songId,
      Value<String> mode,
      Value<String> intent,
      Value<String> queuePositionType,
      Value<String> rawText,
      Value<String> spokenText,
      Value<String?> audioPath,
      Value<String?> voiceId,
      Value<String> createdAt,
      Value<String?> updatedAt,
      Value<int> rowid,
    });

class $$DjSpeechCacheTableFilterComposer
    extends Composer<_$AppDatabase, $DjSpeechCacheTable> {
  $$DjSpeechCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queuePositionType => $composableBuilder(
    column: $table.queuePositionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceId => $composableBuilder(
    column: $table.voiceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DjSpeechCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $DjSpeechCacheTable> {
  $$DjSpeechCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queuePositionType => $composableBuilder(
    column: $table.queuePositionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceId => $composableBuilder(
    column: $table.voiceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DjSpeechCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $DjSpeechCacheTable> {
  $$DjSpeechCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get intent =>
      $composableBuilder(column: $table.intent, builder: (column) => column);

  GeneratedColumn<String> get queuePositionType => $composableBuilder(
    column: $table.queuePositionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get spokenText => $composableBuilder(
    column: $table.spokenText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<String> get voiceId =>
      $composableBuilder(column: $table.voiceId, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DjSpeechCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DjSpeechCacheTable,
          DjSpeechCacheRow,
          $$DjSpeechCacheTableFilterComposer,
          $$DjSpeechCacheTableOrderingComposer,
          $$DjSpeechCacheTableAnnotationComposer,
          $$DjSpeechCacheTableCreateCompanionBuilder,
          $$DjSpeechCacheTableUpdateCompanionBuilder,
          (
            DjSpeechCacheRow,
            BaseReferences<
              _$AppDatabase,
              $DjSpeechCacheTable,
              DjSpeechCacheRow
            >,
          ),
          DjSpeechCacheRow,
          PrefetchHooks Function()
        > {
  $$DjSpeechCacheTableTableManager(_$AppDatabase db, $DjSpeechCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DjSpeechCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DjSpeechCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DjSpeechCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> intent = const Value.absent(),
                Value<String> queuePositionType = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String> spokenText = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<String?> voiceId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DjSpeechCacheCompanion(
                id: id,
                songId: songId,
                mode: mode,
                intent: intent,
                queuePositionType: queuePositionType,
                rawText: rawText,
                spokenText: spokenText,
                audioPath: audioPath,
                voiceId: voiceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String songId,
                required String mode,
                required String intent,
                required String queuePositionType,
                required String rawText,
                required String spokenText,
                Value<String?> audioPath = const Value.absent(),
                Value<String?> voiceId = const Value.absent(),
                required String createdAt,
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DjSpeechCacheCompanion.insert(
                id: id,
                songId: songId,
                mode: mode,
                intent: intent,
                queuePositionType: queuePositionType,
                rawText: rawText,
                spokenText: spokenText,
                audioPath: audioPath,
                voiceId: voiceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DjSpeechCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DjSpeechCacheTable,
      DjSpeechCacheRow,
      $$DjSpeechCacheTableFilterComposer,
      $$DjSpeechCacheTableOrderingComposer,
      $$DjSpeechCacheTableAnnotationComposer,
      $$DjSpeechCacheTableCreateCompanionBuilder,
      $$DjSpeechCacheTableUpdateCompanionBuilder,
      (
        DjSpeechCacheRow,
        BaseReferences<_$AppDatabase, $DjSpeechCacheTable, DjSpeechCacheRow>,
      ),
      DjSpeechCacheRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$SongStatsTableTableManager get songStats =>
      $$SongStatsTableTableManager(_db, _db.songStats);
  $$ListeningEventsTableTableManager get listeningEvents =>
      $$ListeningEventsTableTableManager(_db, _db.listeningEvents);
  $$ContextStatsTableTableManager get contextStats =>
      $$ContextStatsTableTableManager(_db, _db.contextStats);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistSongsTableTableManager get playlistSongs =>
      $$PlaylistSongsTableTableManager(_db, _db.playlistSongs);
  $$PronunciationFixesTableTableManager get pronunciationFixes =>
      $$PronunciationFixesTableTableManager(_db, _db.pronunciationFixes);
  $$RecentDjLinesTableTableManager get recentDjLines =>
      $$RecentDjLinesTableTableManager(_db, _db.recentDjLines);
  $$DjSpeechCacheTableTableManager get djSpeechCache =>
      $$DjSpeechCacheTableTableManager(_db, _db.djSpeechCache);
}
