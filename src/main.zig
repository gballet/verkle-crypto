const std = @import("std");

pub fn main() !void {}

test "bandersnatch" {
    _ = @import("bandersnatch/bandersnatch.zig");
}

test "banderwagon" {
    _ = @import("banderwagon/banderwagon.zig");
}

test "crs" {
    _ = @import("crs/crs.zig");
}

test "msm" {
    _ = @import("msm/precomp.zig");
    _ = @import("msm/pippenger.zig");
}

test "fields" {
    _ = @import("fields/fields.zig");
}

test "ipa" {
    _ = @import("ipa/transcript.zig");
    _ = @import("ipa/ipa.zig");
}

test "multiproof" {
    _ = @import("multiproof/multiproof.zig");
}

test "polynomial" {
    _ = @import("polynomial/monomial_basis.zig");
    _ = @import("polynomial/lagrange_basis.zig");
    _ = @import("polynomial/precomputed_weights.zig");
}
