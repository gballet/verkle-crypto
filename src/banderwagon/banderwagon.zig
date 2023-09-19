const std = @import("std");
const Bandersnatch = @import("../bandersnatch/bandersnatch.zig");
// TODO: try to avoid this dependency?
const Fp = Bandersnatch.Fp;
const AffinePoint = Bandersnatch.AffinePoint;
const ExtendedPoint = Bandersnatch.ExtendedPoint;
const ArrayList = std.ArrayList;

// Fr is the scalar field of the Banderwgaon group, which matches with the
// scalar field size of the Bandersnatch primer-ordered subgroup.
pub const Fr = Bandersnatch.Fr;

// TODO(2): Rename to Element?
pub const Banderwagon = struct {
    pub const BytesSize = 32;

    point: ExtendedPoint,

    // initUnsafe is used to create a Banderwagon from a serialized point from a trusted source.
    pub fn initUnsafe(bytes: [BytesSize]u8) Banderwagon {
        return Banderwagon{ .point = ExtendedPoint.initUnsafe(bytes) };
    }

    // fromBytes deserializes an element from a byte array.
    // The spec serialization is the X coordinate in big endian form.
    pub fn fromBytes(bytes: [BytesSize]u8) !Banderwagon {
        var bytes_le = bytes;
        std.mem.reverse(u8, &bytes_le);
        const x = Fp.fromBytes(bytes_le); // TODO: reject if bytes are not canonical?

        if (subgroupCheck(x) != 1) {
            return error.NotInSubgroup;
        }
        const y = try AffinePoint.getYCoordinate(x, true);

        return Banderwagon{ .point = ExtendedPoint.initUnsafe(x, y) };
    }

    // equal returns true if a == b.
    pub fn equal(a: Banderwagon, b: Banderwagon) bool {
        const x1 = a.point.x;
        const y1 = a.point.y;
        const x2 = b.point.x;
        const y2 = b.point.y;

        if (x1.isZero() and y1.isZero()) {
            return false;
        }
        if (x2.isZero() and y2.isZero()) {
            return false;
        }

        const lhs = Fp.mul(x1, y2);
        const rhs = Fp.mul(x2, y1);

        return Fp.equal(lhs, rhs);
    }

    // generator returns the generator of the Banderwagon group.
    pub fn generator() Banderwagon {
        return .{ .point = ExtendedPoint.generator() };
    }

    // add adds two elements of the Banderwagon group.
    pub fn add(self: *Banderwagon, p: Banderwagon, q: Banderwagon) void {
        self.point = ExtendedPoint.add(p.point, q.point);
    }

    // sub subtracts two elements of the Banderwagon group.
    pub fn sub(self: *Banderwagon, p: Banderwagon, q: Banderwagon) void {
        self.point = ExtendedPoint.sub(p.point, q.point);
    }

    // TODO: tests.
    // mapToScalarField maps a Banderwagon point to the scalar field.
    pub fn mapToScalarField(self: Banderwagon) [Fr.BytesSize]u8 {
        const y_inv = self.point.y.inv().?;
        const base_bytes = Fp.mul(self.point.x, y_inv).toBytes();

        return Fr.fromBytes(base_bytes);
    }

    // toBytes serializes an element to a byte array.
    pub fn toBytes(self: Banderwagon) [BytesSize]u8 {
        const affine = self.point.toAffine();
        var x = affine.x;
        if (!affine.y.lexographicallyLargest()) {
            x = Fp.neg(x);
        }

        var bytes = x.toBytes();
        std.mem.reverse(u8, &bytes);

        return bytes;
    }

    // double doubles an element of the Banderwagon group.
    pub fn double(self: *Banderwagon, p: Banderwagon) void {
        self.point = p.point.double();
    }

    // scalarMul multiplies an element of the Banderwagon group by a scalar.
    pub fn scalarMul(element: Banderwagon, scalar: Fr) Banderwagon {
        return Banderwagon{
            .point = ExtendedPoint.scalarMul(element.point, scalar),
        };
    }

    // identity returns the identity element of the Banderwagon group.
    pub fn identity() Banderwagon {
        return Banderwagon{ .point = ExtendedPoint.identity() };
    }

    // msm computes the multi-scalar multiplication of scalars and points.
    pub fn msm(points: []const Banderwagon, scalars: []const Fr) Banderwagon {
        std.debug.assert(scalars.len == points.len);

        // TODO: optimize!
        var res = Banderwagon.identity();
        for (scalars, points) |scalar, point| {
            res.add(res, point.scalarMul(scalar));
        }
        return res;
    }

    fn isOnCurve(self: Banderwagon) bool {
        return self.point.toAffine().isOnCurve();
    }

    fn subgroupCheck(x: Fp) i2 {
        var res = x.mul(x);
        res = res.mul(Bandersnatch.A);
        res = res.neg();
        res = res.add(Fp.one());

        return res.legendre();
    }

    fn twoTorsionPoint() Banderwagon {
        const point = ExtendedPoint.init(Fp.zero(), Fp.one().neg()) catch unreachable;
        return Banderwagon{ .point = point };
    }
};

test "serialize smoke" {
    // Each successive point is a doubling of the previous one
    // The first point is the generator
    const expected_bit_strings = [_][]const u8{
        "4a2c7486fd924882bf02c6908de395122843e3e05264d7991e18e7985dad51e9",
        "43aa74ef706605705989e8fd38df46873b7eae5921fbed115ac9d937399ce4d5",
        "5e5f550494159f38aa54d2ed7f11a7e93e4968617990445cc93ac8e59808c126",
        "0e7e3748db7c5c999a7bcd93d71d671f1f40090423792266f94cb27ca43fce5c",
        "14ddaa48820cb6523b9ae5fe9fe257cbbd1f3d598a28e670a40da5d1159d864a",
        "6989d1c82b2d05c74b62fb0fbdf8843adae62ff720d370e209a7b84e14548a7d",
        "26b8df6fa414bf348a3dc780ea53b70303ce49f3369212dec6fbe4b349b832bf",
        "37e46072db18f038f2cc7d3d5b5d1374c0eb86ca46f869d6a95fc2fb092c0d35",
        "2c1ce64f26e1c772282a6633fac7ca73067ae820637ce348bb2c8477d228dc7d",
        "297ab0f5a8336a7a4e2657ad7a33a66e360fb6e50812d4be3326fab73d6cee07",
        "5b285811efa7a965bd6ef5632151ebf399115fcc8f5b9b8083415ce533cc39ce",
        "1f939fa2fd457b3effb82b25d3fe8ab965f54015f108f8c09d67e696294ab626",
        "3088dcb4d3f4bacd706487648b239e0be3072ed2059d981fe04ce6525af6f1b8",
        "35fbc386a16d0227ff8673bc3760ad6b11009f749bb82d4facaea67f58fc60ed",
        "00f29b4f3255e318438f0a31e058e4c081085426adb0479f14c64985d0b956e0",
        "3fa4384b2fa0ecc3c0582223602921daaa893a97b64bdf94dcaa504e8b7b9e5f",
    };
    var points: [expected_bit_strings.len]Banderwagon = undefined;
    var point = Banderwagon.generator();

    // Check that encoding algorithm gives expected results
    for (expected_bit_strings, 0..) |bit_string, i| {
        const byts = std.fmt.bytesToHex(point.toBytes(), std.fmt.Case.lower);
        try std.testing.expectEqualSlices(u8, bit_string, &byts);

        points[i] = point;
        point.double(point);
    }

    // Check that decoding algorithm is correct
    for (expected_bit_strings, 0..) |bit_string, i| {
        const expected_point = points[i];

        var byts: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&byts, bit_string);
        const decoded_point = try Banderwagon.fromBytes(byts);
        try std.testing.expect(decoded_point.equal(expected_point));
    }
}

test "two torsion" {
    // two points which differ by the order two point (0,-1) should be
    // considered the same
    const gen = Banderwagon.generator();
    const two_torsion = Banderwagon.twoTorsionPoint();

    var result = Banderwagon.identity();
    result.add(gen, two_torsion);

    try std.testing.expect(result.equal(gen));
}
