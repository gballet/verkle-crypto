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
        pub const BitSize = @bitSizeOf(u256) - @clz(mod);
        pub const BytesSize = @sizeOf(u256);
        pub const Modulo = mod;
        pub const QMinOneDiv2 = (Modulo - 1) / 2;

        const Self = @This();
        const base_zero = val: {
            var bz: F.MontgomeryDomainFieldElement = undefined;
            F.fromBytes(&bz, [_]u8{0} ** BytesSize);
            break :val Self{ .fe = bz };
        };

        fe: F.MontgomeryDomainFieldElement,

        pub fn fromInteger(num: u256) Self {
            var lbe: [BytesSize]u8 = [_]u8{0} ** BytesSize;
            std.mem.writeInt(u256, lbe[0..], num % Modulo, .little);

            var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromBytes(&nonMont, lbe);
            var mont: F.MontgomeryDomainFieldElement = undefined;
            F.toMontgomery(&mont, nonMont);

            return Self{ .fe = mont };
        }

        pub fn zero() Self {
            return base_zero;
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
                non_mont[i] = std.mem.readInt(u64, bytes[i * 8 .. (i + 1) * 8], .little);
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
                std.mem.writeInt(u64, ret[i * 8 .. (i + 1) * 8], non_mont[i], .little);
            }

            return ret;
        }

        pub fn lexographicallyLargest(self: Self) bool {
            const selfNonMont = self.toInteger();
            return selfNonMont > QMinOneDiv2;
        }

        pub fn fromMontgomery(self: Self) F.NonMontgomeryDomainFieldElement {
            var nonMont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&nonMont, self.fe);
            return nonMont;
        }
        pub fn add(self: Self, other: Self) Self {
            var ret: F.NonMontgomeryDomainFieldElement = undefined;
            F.add(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub fn sub(self: Self, other: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub fn mul(self: Self, other: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.mul(&ret, self.fe, other.fe);
            return Self{ .fe = ret };
        }

        pub fn mulBy5(self: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.add(&ret, self.fe, self.fe);
            F.add(&ret, ret, ret);
            F.add(&ret, ret, self.fe);
            return Self{ .fe = ret };
        }

        pub fn neg(self: Self) Self {
            var ret: F.MontgomeryDomainFieldElement = undefined;
            F.sub(&ret, base_zero.fe, self.fe);
            return Self{ .fe = ret };
        }

        pub fn isZero(self: Self) bool {
            return self.equal(base_zero);
        }

        pub fn isOne(self: Self) bool {
            return self.equal(one());
        }

        pub fn square(self: Self) Self {
            return self.mul(self);
        }

        pub fn pow2(self: Self, comptime exponent: u8) Self {
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

        pub fn batchInv(out: []Self, in: []const Self) !void {
            std.debug.assert(out.len == in.len);

            var acc = one();
            for (0..in.len) |i| {
                out[i] = acc;
                acc = mul(acc, in[i]);
            }
            acc = acc.inv() orelse return error.CantInvertZeroElement;
            for (0..in.len) |i| {
                out[in.len - i - 1] = mul(out[in.len - i - 1], acc);
                acc = mul(acc, in[in.len - i - 1]);
            }
        }

        pub fn inv(self: Self) ?Self {
            var r: u256 = Modulo;
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
                t = t + Modulo;
            }

            return Self.fromInteger(@intCast(t));
        }

        pub fn div(self: Self, den: Self) !Self {
            const den_inv = den.inv() orelse return error.DivisionByZero;
            return self.mul(den_inv);
        }

        pub fn equal(self: Self, other: Self) bool {
            return std.mem.eql(u64, &self.fe, &other.fe);
        }

        pub fn toInteger(self: Self) u256 {
            var non_mont: F.NonMontgomeryDomainFieldElement = undefined;
            F.fromMontgomery(&non_mont, self.fe);

            var bytes: [BytesSize]u8 = [_]u8{0} ** BytesSize;
            F.toBytes(&bytes, non_mont);

            return std.mem.readInt(u256, &bytes, .little);
        }

        pub fn sqrt(x: Self) ?Self {
            if (x.isZero()) {
                return null;
            }
            var candidate: Self = undefined;
            var root_of_unity: Self = undefined;
            fastsqrt.sqrtAlg_ComputeRelevantPowers(x, &candidate, &root_of_unity);
            if (!fastsqrt.invSqrtEqDyadic(&root_of_unity)) {
                return null;
            }

            return mul(candidate, root_of_unity);
        }

        pub fn legendre(a: Self) i2 {
            // Compute the Legendre symbol a|p using
            // Euler's criterion. p is a prime, a is
            // relatively prime to p (if p divides
            // a, then a|p = 0)
            // Returns 1 if a has a square root modulo
            // p, -1 otherwise.
            const ls = a.pow((Modulo - 1) / 2);

            const modulo_minus_one = comptime fromInteger(Modulo - 1);
            if (ls.equal(modulo_minus_one)) {
                return -1;
            } else if (ls.isZero()) {
                return 0;
            }
            return 1;
        }
    };
}
