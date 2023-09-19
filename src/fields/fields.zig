const std = @import("std");
const builtin = @import("builtin");
const fastsqrt = @import("sqrt.zig");
const ArrayList = std.ArrayList;

pub const BandersnatchFields = struct {
    // BaseField is the base field of the Bandersnatch curve.
    pub const BaseField = Field(@import("gen_fp.zig"), 52435875175126190479447740508185965837690552500527637822603658699938581184513);
    // ScalarField is the scalar field of the Bandersnatch prime-order subgroup.
    pub const ScalarField = Field(@import("gen_fr.zig"), 13108968793781547619861935127046491459309155893440570251786403306729687672801);
};

fn Field(comptime F: type, comptime mod: u256) type {
    return struct {
        pub const BytesSize = 32;
        pub const MODULO = mod;
        pub const Q_MIN_ONE_DIV_2 = (MODULO - 1) / 2;

        comptime {
            std.debug.assert(@bitSizeOf(u256) == BytesSize * 8);
        }

        const Self = @This();
        const baseZero = val: {
            var bz: F.MontgomeryDomainFieldElement = undefined;
            F.fromBytes(&bz, [_]u8{0} ** BytesSize);
            break :val Self{ .fe = bz };
        };

        fe: F.MontgomeryDomainFieldElement,

        pub fn fromInteger(num: u256) Self {
            var lbe: [BytesSize]u8 = [_]u8{0} ** BytesSize;
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

        pub fn fromBytes(bytes: [BytesSize]u8) Self {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            inline for (0..4) |i| {
                non_mont[i] = std.mem.readIntSlice(u64, bytes[i * 8 .. (i + 1) * 8], std.builtin.Endian.Little);
            }
            var ret: Self = undefined;
            F.toMontgomery(&ret.fe, non_mont);

            return ret;
        }

        pub fn toBytes(self: Self) [BytesSize]u8 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&non_mont, self.fe);
            var ret: [BytesSize]u8 = undefined;
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
            return self.equal(baseZero);
        }

        pub fn isOne(self: Self) bool {
            return self.equal(one());
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

        pub fn equal(self: Self, other: Self) bool {
            return std.mem.eql(u64, &self.fe, &other.fe);
        }

        pub inline fn toInteger(self: Self) u256 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&non_mont, self.fe);

            var bytes: [BytesSize]u8 = [_]u8{0} ** BytesSize;
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

        pub fn legendre(a: Self) i2 {
            // Compute the Legendre symbol a|p using
            // Euler's criterion. p is a prime, a is
            // relatively prime to p (if p divides
            // a, then a|p = 0)
            // Returns 1 if a has a square root modulo
            // p, -1 otherwise.
            const ls = a.pow((MODULO - 1) / 2);

            const moduloMinusOne = comptime fromInteger(MODULO - 1);
            if (ls.equal(moduloMinusOne)) {
                return -1;
            } else if (ls.isZero()) {
                return 0;
            }
            return 1;
        }
    };
}
