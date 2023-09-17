const std = @import("std");
const builtin = @import("builtin");
const fastsqrt = @import("sqrt.zig");
const ArrayList = std.ArrayList;

pub const Fp = BandersnatchField(@import("gen_fp.zig"), 52435875175126190479447740508185965837690552500527637822603658699938581184513);
pub const Fr = BandersnatchField(@import("gen_fr.zig"), 13108968793781547619861935127046491459309155893440570251786403306729687672801);

fn BandersnatchField(comptime F: type, comptime mod: u256) type {
    return struct {
        pub const BYTE_LEN = 32;
        pub const MODULO = mod;

        comptime {
            std.debug.assert(@bitSizeOf(u256) == BYTE_LEN * 8);
        }

        const Self = @This();
        const Q_MIN_ONE_DIV_2 = (MODULO - 1) / 2;
        const baseZero = val: {
            var bz: F.MontgomeryDomainFieldElement = undefined;
            F.fromBytes(&bz, [_]u8{0} ** BYTE_LEN);
            break :val Self{ .fe = bz };
        };

        fe: F.MontgomeryDomainFieldElement,

        pub fn fromInteger(num: u256) Self {
            var lbe: [BYTE_LEN]u8 = [_]u8{0} ** BYTE_LEN;
            std.mem.writeInt(u256, lbe[0..], num % MODULO, std.builtin.Endian.Little);

            var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromBytes(&nonMont, lbe);
            var mont: F.MontgomeryDomainFieldElement = undefined;
            F.toMontgomery(&mont, nonMont);

            return Self{ .fe = mont };
        }

        pub fn zero() Self {
            return baseZero;
        }

        pub fn one() Self {
            const oneValue = comptime blk: {
                var baseOne: F.MontgomeryDomainFieldElement = undefined;
                F.setOne(&baseOne);
                break :blk Self{ .fe = baseOne };
            };
            return oneValue;
        }

        pub fn from_bytes(bytes: [BYTE_LEN]u8) Self {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            inline for (0..4) |i| {
                non_mont[i] = std.mem.readIntSlice(u64, bytes[i * 8 .. (i + 1) * 8], std.builtin.Endian.Little);
            }
            var ret: Self = undefined;
            F.toMontgomery(&ret.fe, non_mont);

            return ret;
        }

        pub fn to_bytes(self: Self) [BYTE_LEN]u8 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&non_mont, self.fe);
            var ret: [BYTE_LEN]u8 = undefined;
            inline for (0..4) |i| {
                std.mem.writeIntSlice(u64, ret[i * 8 .. (i + 1) * 8], non_mont[i], std.builtin.Endian.Little);
            }

            return ret;
        }

        pub fn lexographicallyLargest(self: Self) bool {
            const selfNonMont = self.toInteger();
            return selfNonMont > Q_MIN_ONE_DIV_2;
        }

        pub fn fromMontgomery(self: Self) F.NonMontgomeryDomainFieldElement {
            var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&nonMont, self.fe);
            return nonMont;
        }

        // TODO(jsign): optimize.
        pub fn multiInv(gpa: std.mem.Allocator, values: []Self) !ArrayList(Self) {
            var ret = try ArrayList(Self).initCapacity(gpa, values.len);
            for (values) |v| {
                const vi = v.inv() orelse return error.InverseDoesntExist;
                ret.appendAssumeCapacity(vi);
            }
            return ret;
        }

        pub fn add(self: Self, other: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.add(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub fn sub(self: Self, other: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub inline fn mul(self: Self, other: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.mul(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub fn neg(self: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(&ret, baseZero.fe, self.fe);
            return Self{ .fe = ret };
        }

        pub fn isZero(self: Self) bool {
            return self.eq(baseZero);
        }

        pub fn isOne(self: Self) bool {
            return self.eq(one());
        }

        pub fn square(self: Self) Self {
            return self.mul(self);
        }

        pub inline fn pow2(self: Self, comptime exponent: u8) Self {
            var ret = self;
            inline for (exponent) |_| {
                ret = ret.mul(ret);
            }
            return ret;
        }

        pub fn pow(self: Self, exponent: u256) Self {
            var res = one();
            var exp = exponent;
            var base = self;

            while (exp > 0) : (exp = exp / 2) {
                if (exp & 1 == 1) {
                    res = res.mul(base);
                }
                base = base.mul(base);
            }
            return res;
        }

        pub fn inv(self: Self) ?Self {
            var r: u256 = MODULO;
            var t: i512 = 0;

            var newr: u256 = self.toInteger();
            var newt: i512 = 1;

            while (newr != 0) {
                const quotient = r / newr;
                const tempt = t - quotient * newt;
                const tempr = r - quotient * newr;

                r = newr;
                t = newt;
                newr = tempr;
                newt = tempt;
            }

            // Not invertible
            if (r > 1) {
                return null;
            }

            if (t < 0) {
                t = t + MODULO;
            }

            return Self.fromInteger(@intCast(t));
        }

        pub fn div(self: Self, den: Self) !Self {
            const denInv = den.inv() orelse return error.DivisionByZero;
            return self.mul(denInv);
        }

        pub fn eq(self: Self, other: Self) bool {
            return std.mem.eql(u64, &self.fe, &other.fe);
        }

        pub inline fn toInteger(self: Self) u256 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&non_mont, self.fe);

            var bytes: [BYTE_LEN]u8 = [_]u8{0} ** BYTE_LEN;
            F.toBytes(&bytes, non_mont);

            return std.mem.readInt(u256, &bytes, std.builtin.Endian.Little);
        }

        pub fn sqrt(x: Self) ?Self {
            if (x.isZero()) {
                return null;
            }
            var candidate: Self = undefined;
            var rootOfUnity: Self = undefined;
            fastsqrt.sqrtAlg_ComputeRelevantPowers(x, &candidate, &rootOfUnity);
            if (!fastsqrt.invSqrtEqDyadic(&rootOfUnity)) {
                return null;
            }

            return mul(candidate, rootOfUnity);
        }

        pub fn sqrt_slow(a: Self) ?Self {
            // Find a quadratic residue (mod p) of 'a'. p
            // must be an odd prime.
            // Solve the congruence of the form:
            //     x^2 = a (mod p)
            // And returns x. Note that p - x is also a root.
            // 0 is returned is no square root exists for
            // these a and p.
            // The Tonelli-Shanks algorithm is used (except
            // for some simple cases in which the solution
            // is known from an identity). This algorithm
            // runs in polynomial time (unless the
            // generalized Riemann hypothesis is false).

            // Simple cases
            if (Self.legendre(a) != 1) {
                return null;
            } else if (a.isZero()) {
                return Self.zero();
            }

            // Partition p-1 to s * 2^e for an odd s (i.e.
            // reduce all the powers of 2 from p-1)
            const s_e = comptime blk: {
                var s = MODULO - 1;
                var e = 0;
                while (s % 2 == 0) {
                    s = s / 2;
                    e = e + 1;
                }
                break :blk .{ .s = s, .e = e };
            };
            const s = s_e.s;
            const e = s_e.e;

            // Find some 'n' with a legendre symbol n|p = -1.
            // Shouldn't take long.
            // TODO(jsign): switch to comptime again but optionally.
            const n = blk: {
                var n = fromInteger(2);
                while (legendre(n) != -1) {
                    n = n.add(one());
                }
                break :blk n;
            };

            // Here be dragons!
            // Read the paper "Square roots from 1; 24, 51,
            // 10 to Dan Shanks" by Ezra Brown for more
            // information

            // x is a guess of the square root that gets better
            // with each iteration.
            // b is the "fudge factor" - by how much we're off
            // with the guess. The invariant x^2 = ab (mod p)
            // is maintained throughout the loop.
            // g is used for successive powers of n to update
            // both a and b
            // r is the exponent - decreases with each update
            var x = a.pow((s + 1) / 2);
            var b = a.pow(s);
            var g = n.pow(s);
            var r: u256 = e;

            while (true) {
                var t = b;
                var m: u256 = 0;
                blk: while (m < r) : (m = m + 1) {
                    if (t.isOne()) {
                        break :blk;
                    }
                    t = t.pow(2);
                }

                if (m == 0) {
                    return x;
                }

                const gs = g.pow(std.math.pow(u256, 2, r - m - 1));
                g = gs.mul(gs);
                x = x.mul(gs);
                b = b.mul(g);
                r = m;
            }
            unreachable;
        }

        pub fn legendre(a: Self) i2 {
            // Compute the Legendre symbol a|p using
            // Euler's criterion. p is a prime, a is
            // relatively prime to p (if p divides
            // a, then a|p = 0)
            // Returns 1 if a has a square root modulo
            // p, -1 otherwise.
            const ls = a.pow((MODULO - 1) / 2);

            const moduloMinusOne = comptime fromInteger(MODULO - 1);
            if (ls.eq(moduloMinusOne)) {
                return -1;
            } else if (ls.isZero()) {
                return 0;
            }
            return 1;
        }
    };
}

// TODO(jsign): test with Fr.

test "one" {
    const oneFromInteger = Fp.fromInteger(1);
    const oneFromAPI = Fp.one();

    try std.testing.expect(oneFromInteger.eq(oneFromAPI));
}

test "zero" {
    const zeroFromInteger = Fp.fromInteger(0);
    const zeroFromAPI = Fp.zero();

    try std.testing.expect(zeroFromInteger.eq(zeroFromAPI));
}

test "lexographically largest" {
    try std.testing.expect(!Fp.fromInteger(0).lexographicallyLargest());
    try std.testing.expect(!Fp.fromInteger(Fp.Q_MIN_ONE_DIV_2).lexographicallyLargest());

    try std.testing.expect(Fp.fromInteger(Fp.Q_MIN_ONE_DIV_2 + 1).lexographicallyLargest());
    try std.testing.expect(Fp.fromInteger(Fp.MODULO - 1).lexographicallyLargest());
}

test "from and to bytes" {
    const cases = [_]Fp{ Fp.fromInteger(0), Fp.fromInteger(1), Fp.fromInteger(Fp.Q_MIN_ONE_DIV_2), Fp.fromInteger(Fp.MODULO - 1) };

    for (cases) |fe| {
        const bytes = fe.to_bytes();
        const fe2 = Fp.from_bytes(bytes);
        try std.testing.expect(fe.eq(fe2));

        const bytes2 = fe2.to_bytes();
        try std.testing.expectEqualSlices(u8, &bytes, &bytes2);
    }
}

test "to integer" {
    try std.testing.expect(Fp.fromInteger(0).toInteger() == 0);
    try std.testing.expect(Fp.fromInteger(1).toInteger() == 1);
    try std.testing.expect(Fp.fromInteger(100).toInteger() == 100);
}

test "add sub mul neg" {
    const got = Fp.fromInteger(10).mul(Fp.fromInteger(20)).add(Fp.fromInteger(30)).sub(Fp.fromInteger(40)).add(Fp.fromInteger(Fp.MODULO));
    const want = Fp.fromInteger(190);
    try std.testing.expect(got.eq(want));

    const gotneg = got.neg();
    const wantneg = Fp.fromInteger(Fp.MODULO - 190);
    try std.testing.expect(gotneg.eq(wantneg));
}

test "inv" {
    const types = [_]type{Fp};

    inline for (types) |T| {
        try std.testing.expect(T.fromInteger(0).inv() == null);

        const one = T.one();
        const cases = [_]T{ T.fromInteger(2), T.fromInteger(42), T.fromInteger(T.MODULO - 1) };
        for (cases) |fe| {
            try std.testing.expect(fe.mul(fe.inv().?).eq(one));
        }
    }
}

test "sqrt" {
    // Test that a non-residue has no square root.
    const nonresidue = Fp.fromInteger(42);
    try std.testing.expect(nonresidue.legendre() != 1);
    try std.testing.expect(nonresidue.sqrt() == null);

    // Test that a residue has a square root and sqrt(b)^2=b.
    const b = Fp.fromInteger(44);
    try std.testing.expect(b.legendre() == 1);

    const b_sqrt = b.sqrt().?;
    const b_sqrt_sqr = b_sqrt.mul(b_sqrt);

    try std.testing.expect(b.eq(b_sqrt_sqr));
}
