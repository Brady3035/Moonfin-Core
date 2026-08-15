import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';

void main() {
  test('the my rating sort never reaches plain items api consumers', () {
    expect(
      LibrarySortBy.itemsApiValues,
      isNot(contains(LibrarySortBy.myRating)),
    );
    expect(LibrarySortBy.myRating.usesDedicatedEndpoint, isTrue);
    // The fallback for consumers without the dedicated path has to be a
    // value the items api accepts.
    expect(LibrarySortBy.myRating.apiValue, 'SortName');
  });
}
