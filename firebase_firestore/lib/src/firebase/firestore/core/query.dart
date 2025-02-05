// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:collection/collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/bound.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/relation_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Represents the internal structure of a Firestore Query
class Query {
  /// Initializes a Query with all of its components directly.
  const Query(
    this.path, {
    this.filters = const <Filter>[],
    this.explicitSortOrder = const <OrderBy>[],
    int limit = noLimit,
    Bound startAt,
    Bound endAt,
  })  : _limit = limit,
        _startAt = startAt,
        _endAt = endAt;

  static const int noLimit = -1;

  static final OrderBy keyOrderingAsc =
      OrderBy.getInstance(OrderByDirection.ascending, FieldPath.keyPath);

  static final OrderBy keyOrderingDesc =
      OrderBy.getInstance(OrderByDirection.descending, FieldPath.keyPath);

  /// Returns the list of ordering constraints that were explicitly requested on the query by the
  /// user.
  ///
  /// Note that the actual query performed might add additional sort orders to match the behavior of
  /// the backend.
  final List<OrderBy> explicitSortOrder;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The base path of the query.
  final ResourcePath path;

  final int _limit;

  /// An optional bound to start the query at.
  final Bound _startAt;

  /// An optional bound to end the query at.
  final Bound _endAt;

  /// Returns true if this Query is for a specific document.
  bool get isDocumentQuery {
    return DocumentKey.isDocumentKey(path) && filters.isEmpty;
  }

  /// The maximum number of results to return. If there is no limit on the query, then this will
  /// cause an assertion failure.
  int getLimit() {
    hardAssert(hasLimit, 'Called getLimit when no limit was set');
    return _limit;
  }

  bool get hasLimit => _limit != noLimit;

  /// Returns a new [Query] with the given limit on how many results can be returned.
  ///
  /// [limit] represents the maximum number of results to return. If `limit == noLimit`, then no
  /// limit is applied. Otherwise, if `limit <= 0`, behavior is unspecified.
  Query limit(int limit) => copyWith(limit: limit);

  /// An optional bound to start the query at.
  Bound getStartAt() => _startAt;

  /// An optional bound to end the query at.
  Bound getEndAt() => _endAt;

  /// Returns the first field in an order-by constraint, or null if none.
  FieldPath get firstOrderByField {
    if (explicitSortOrder.isEmpty) {
      return null;
    }
    return explicitSortOrder[0].field;
  }

  /// Returns the field of the first filter on this Query that's an inequality,
  /// or null if none.
  FieldPath get inequalityField {
    for (Filter filter in filters) {
      if (filter is RelationFilter) {
        final RelationFilter relationFilter = filter;
        if (relationFilter.isInequality) {
          return relationFilter.field;
        }
      }
    }
    return null;
  }

  bool get hasArrayContainsFilter {
    for (Filter filter in filters) {
      if (filter is RelationFilter) {
        final RelationFilter relationFilter = filter;
        if (relationFilter.operator == FilterOperator.arrayContains) {
          return true;
        }
      }
    }
    return false;
  }

  /// Creates a new Query with an additional filter.
  ///
  /// [filter] is the predicate to filter by.
  Query filter(Filter filter) {
    hardAssert(!DocumentKey.isDocumentKey(path), 'No filter is allowed for document query');

    FieldPath newInequalityField;
    if (filter is RelationFilter && filter.isInequality) {
      newInequalityField = filter.field;
    }

    final FieldPath queryInequalityField = inequalityField;
    hardAssert(
        queryInequalityField == null ||
            newInequalityField == null ||
            queryInequalityField == newInequalityField,
        'Query must only have one inequality field');

    hardAssert(
        explicitSortOrder.isEmpty ||
            newInequalityField == null ||
            explicitSortOrder[0].field == newInequalityField,
        'First orderBy must match inequality field');

    final List<Filter> updatedFilter = List<Filter>.from(filters);
    updatedFilter.add(filter);
    return copyWith(filters: updatedFilter);
  }

  /// Creates a new Query with an additional ordering constraint.
  ///
  /// [order] is the key and direction to order by.
  Query orderBy(OrderBy order) {
    if (DocumentKey.isDocumentKey(path)) {
      throw fail('No ordering is allowed for document query');
    }
    if (explicitSortOrder.isEmpty) {
      final FieldPath inequality = inequalityField;
      if (inequality != null && inequality != order.field) {
        throw fail('First orderBy must match inequality field');
      }
    }
    final List<OrderBy> updatedSortOrder = List<OrderBy>.from(explicitSortOrder);
    updatedSortOrder.add(order);
    return copyWith(explicitSortOrder: updatedSortOrder);
  }

  /// Creates a new Query starting at the provided bound.
  /// The [bound] to end this query at.
  Query startAt(Bound bound) => copyWith(startAt: bound);

  /// Creates a new Query ending at the provided bound.
  ///
  /// The [bound] to end this query at.
  Query endAt(Bound bound) => copyWith(endAt: bound);

  /// Returns the full list of ordering constraints on the query.
  ///
  /// This might include additional sort orders added implicitly to match the
  /// backend behavior.
  List<OrderBy> get orderByConstraints {
    final FieldPath inequalityField = this.inequalityField;
    if (inequalityField != null && firstOrderByField == null) {
      // In order to implicitly add key ordering, we must also add the
      // inequality filter field for it to be a valid query. Note that the
      // default inequality field and key ordering is ascending.
      if (inequalityField.isKeyField) {
        return <OrderBy>[keyOrderingAsc];
      } else {
        return <OrderBy>[
          OrderBy.getInstance(OrderByDirection.ascending, inequalityField),
          keyOrderingAsc
        ];
      }
    } else {
      final List<OrderBy> res = <OrderBy>[];
      bool foundKeyOrdering = false;
      for (OrderBy explicit in explicitSortOrder) {
        res.add(explicit);
        if (explicit.field == FieldPath.keyPath) {
          foundKeyOrdering = true;
        }
      }
      if (!foundKeyOrdering) {
        // The direction of the implicit key ordering always matches the
        // direction of the last explicit sort order
        final OrderByDirection lastDirection = explicitSortOrder.isNotEmpty
            ? explicitSortOrder[explicitSortOrder.length - 1].direction
            : OrderByDirection.ascending;
        res.add(lastDirection == OrderByDirection.ascending ? keyOrderingAsc : keyOrderingDesc);
      }
      return res;
    }
  }

  bool _matchesPath(Document doc) {
    final ResourcePath docPath = doc.key.path;
    if (DocumentKey.isDocumentKey(path)) {
      return path == docPath;
    } else {
      return path.isPrefixOf(docPath) && path.length == docPath.length - 1;
    }
  }

  bool _matchesFilters(Document doc) {
    for (Filter filter in filters) {
      if (!filter.matches(doc)) {
        return false;
      }
    }
    return true;
  }

  /// A document must have a value for every ordering clause in order to show up in the results.
  bool _matchesOrderBy(Document doc) {
    for (OrderBy order in explicitSortOrder) {
      // order by key always matches
      if (order.field != FieldPath.keyPath && doc.getField(order.field) == null) {
        return false;
      }
    }
    return true;
  }

  /// Makes sure a document is within the bounds, if provided.
  bool _matchesBounds(Document doc) {
    if (_startAt != null && !_startAt.sortsBeforeDocument(orderByConstraints, doc)) {
      return false;
    }
    if (_endAt != null && _endAt.sortsBeforeDocument(orderByConstraints, doc)) {
      return false;
    }
    return true;
  }

  /// Returns true if the document matches the constraints of this query.
  bool matches(Document doc) {
    return _matchesPath(doc) && _matchesOrderBy(doc) && _matchesFilters(doc) && _matchesBounds(doc);
  }

  /// Returns a comparator that will sort documents according to this Query's sort order.
  Comparator<Document> get comparator => QueryComparator(orderByConstraints).comparator;

  /// Returns a canonical string representing this query. This should match the iOS and Android
  /// canonical ids for a query exactly.
  String get canonicalId {
    // TODO: Cache the return value.
    final StringBuffer builder = StringBuffer();
    builder.write(path.canonicalString);

    // Add filters.
    builder.write('|f:');
    for (Filter filter in filters) {
      builder.write(filter.canonicalId);
    }

    // Add order by.
    builder.write('|ob:');
    for (OrderBy orderBy in orderByConstraints) {
      builder.write(orderBy.field.canonicalString);
      builder.write(orderBy.direction == OrderByDirection.ascending ? 'asc' : 'desc');
    }

    // Add limit.
    if (hasLimit) {
      builder.write('|l:');
      builder.write(limit);
    }

    if (_startAt != null) {
      builder.write('|lb:');
      builder.write(_startAt.canonicalString());
    }

    if (_endAt != null) {
      builder.write('|ub:');
      builder.write(_endAt.canonicalString());
    }

    return builder.toString();
  }

  Query copyWith({
    List<Filter> filters,
    List<OrderBy> explicitSortOrder,
    int limit,
    Bound startAt,
    Bound endAt,
  }) {
    return Query(
      path,
      filters: filters ?? this.filters,
      explicitSortOrder: explicitSortOrder ?? this.explicitSortOrder,
      limit: limit ?? _limit,
      startAt: startAt ?? _startAt,
      endAt: endAt ?? _endAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Query &&
            runtimeType == other.runtimeType &&
            _limit == other._limit &&
            const ListEquality<OrderBy>().equals(orderByConstraints, other.orderByConstraints) &&
            const ListEquality<Filter>().equals(filters, other.filters) &&
            path == other.path &&
            _startAt == other._startAt &&
            _endAt == other._endAt;
  }

  @override
  int get hashCode =>
      const ListEquality<Filter>().hash(filters) * 31 +
      path.hashCode * 31 +
      _limit.hashCode * 31 +
      _startAt.hashCode * 31 +
      _endAt.hashCode * 31 +
      const ListEquality<OrderBy>().hash(orderByConstraints) * 31;

  @override
  String toString() {
    final StringBuffer builder = StringBuffer();
    builder.write('Query(');
    builder.write(path.canonicalString);
    if (filters.isNotEmpty) {
      builder.write(' where ');
      for (int i = 0; i < filters.length; i++) {
        if (i > 0) {
          builder.write(' and ');
        }
        builder.write(filters[i]);
      }
    }

    if (explicitSortOrder.isNotEmpty) {
      builder.write(' order by ');
      for (int i = 0; i < explicitSortOrder.length; i++) {
        if (i > 0) {
          builder.write(', ');
        }
        builder.write(explicitSortOrder[i]);
      }
    }

    builder.write(')');
    return builder.toString();
  }
}

class QueryComparator {
  factory QueryComparator(List<OrderBy> order) {
    bool hasKeyOrdering = false;
    for (OrderBy orderBy in order) {
      hasKeyOrdering = hasKeyOrdering || orderBy.field == FieldPath.keyPath;
    }
    if (!hasKeyOrdering) {
      throw ArgumentError('QueryComparator needs to have a key ordering');
    }

    return QueryComparator._(order);
  }

  const QueryComparator._(this.sortOrder);

  final List<OrderBy> sortOrder;

  Comparator<Document> get comparator {
    return (Document doc1, Document doc2) {
      for (OrderBy order in sortOrder) {
        final int comp = order.compare(doc1, doc2);
        if (comp != 0) {
          return comp;
        }
      }
      return 0;
    };
  }
}
