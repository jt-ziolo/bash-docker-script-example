import assert from "assert";

describe('js basics', function () {
  describe('addition', function () {
    it('2+2 should equal 4', function () {
      assert.equal(2 + 2, 4);
    });
    it('2+2 should equal 5', function () {
      assert.equal(2 + 2, 5);
    });
  });
});
