const z = @import("std");
const urlencode = @import("percent_encoding.zig");

var gpa = z.heap.GeneralPurposeAllocator( .{ .thread_safe = true } ){};
const alloc = gpa.allocator();

const JishoData = struct {
  pub const DataEntry = struct {
    slug: []const u8,
    japanese: []struct {
      word: []const u8,
      reading: ?[]const u8 = null,
    },
    senses: []struct {
      english_definitions: [][]const u8
    },
  };

  data: []DataEntry,
};

/// freed by caller
fn requestWord( word: []const u8 ) ![]const u8 {
  var client = z.http.Client{ .allocator = alloc };
  defer client.deinit();

  const encoded = urlencode.encode_alloc( alloc, word, .{} ) catch |e| {
    z.debug.print( "error encoding word {s}\n", .{ word } ); return e;
  };
  defer alloc.free( encoded );

  const url = try z.fmt.allocPrint( alloc, "https://jisho.org/api/v1/search/words?keyword={s}", .{ encoded } );
  defer alloc.free( url );
  const uri = try z.Uri.parse( url );

  var buf: [4096]u8 = undefined;
  var req = try client.open( .GET, uri, .{ .server_header_buffer = &buf } );
  defer req.deinit();

  req.send() catch |e| { z.debug.print( "error sending request to {s}\n", .{ url } ); return e; };
  req.finish() catch |e| { z.debug.print( "error sending request to {s}\n", .{ url } ); return e; };
  req.wait() catch |e| { z.debug.print( "error sending request to {s}\n", .{ url } ); return e; };

  if( req.response.status != .ok ) {
    z.debug.print( "invalid response from {s}: {d}\n", .{ url, @intFromEnum( req.response.status ) } );
    return error.InvalidResponse;
  }

  var reader = req.reader();
  const body = try reader.readAllAlloc( alloc, 999999 );

  return body;
}

fn formatDef( buf: []u8, data: *JishoData.DataEntry, definition_count: u32, sense_count: u32 ) ![]const u8 {
  if( data.japanese.len == 0 ) {
    return error.NotJapanese;
  }

  var wordb: []const u8 = undefined;
  if( data.japanese[0].reading == null ) {
    wordb = try z.fmt.bufPrint( buf, "{s} - ", .{ data.japanese[0].word } );
  }
  else {
    wordb = try z.fmt.bufPrint( buf, "{s}（{s}） - ", .{ data.japanese[0].word, data.japanese[0].reading.? } );
  }

  var len = wordb.len;
  var engb: []const u8 = buf[len..];
  for( data.senses, 0.. ) |sense, i| {
    if( i > sense_count ) {
      engb = try z.fmt.bufPrint( buf[len..], ", etc...", .{} );
      len += engb.len;
      break;
    }

    for( sense.english_definitions, 0.. ) |definition, j| {
      if( j > definition_count )
        break
      else if( j < definition_count and j < sense.english_definitions.len - 1 )
        engb = try z.fmt.bufPrint( buf[len..], "{s}/", .{ definition } )
      else
        engb = try z.fmt.bufPrint( buf[len..], "{s}", .{ definition } );
      len += engb.len;
    }

    if( i < sense_count and i < data.senses.len - 1 ) {
      engb = try z.fmt.bufPrint( buf[len..], ", ", .{} );
      len += engb.len;
    }
  }

  return buf[0..len];
}

fn parseArgs( definitions_count: *u32, senses_count: *u32 ) ![]const u8 {
  const args = try z.process.argsAlloc( alloc );
  defer z.process.argsFree( alloc, args );
  if( args.len < 2 ) {
    z.debug.print( "usage: {s} [-d <definitions> -s <senses>] <word>\n", .{args[0]} );
    return error.InvalidArgs;
  }

  var usedargs: u32 = 0;
  for( args, 0.. ) |arg, i| {
    if( z.mem.eql( u8, arg, "-d" ) ) {
      if( i == args.len - 1 )
        return error.InvalidDefinitionCount;

      definitions_count.* = z.fmt.parseInt( u32, args[i + 1], 10 ) catch return error.InvalidSenseCount;
      usedargs += 1;
    }
    if( z.mem.eql( u8, arg, "-s" ) ) {
      if( i == args.len - 1 )
        return error.InvalidSenseCount;

      senses_count.* = z.fmt.parseInt( u32, args[i + 1], 10 ) catch return error.InvalidSenseCount;
      usedargs += 1;
    }
  }

  if( args.len - usedargs < 2 ) {
    z.debug.print( "usage: {s} [-d <definitions> -s <senses>] <word>\n", .{args[0]} );
    z.process.argsFree( alloc, args );
    return error.InvalidArgCount;
  }

  return alloc.dupe( u8, args[args.len - 1] );
}

pub fn main() !void {
  var definitions_count: u32 = 3;
  var senses_count: u32 = 4;

  const word = parseArgs( &definitions_count, &senses_count ) catch |e| {
    z.debug.print( "failed to parse arguments: {any}\n", .{e} );
    return;
  };
  const res = requestWord( word ) catch |e| {
    z.debug.print( "failed to request word: {any}\n", .{e} );
    return;
  };
  const parsed = z.json.parseFromSlice( JishoData, alloc, res, .{ .ignore_unknown_fields = true } ) catch |e| {
    z.debug.print( "failed to parse response body ({any}): {s}\n", .{e, res} );
    return;
  };
  if( parsed.value.data.len == 0 ) {
    z.debug.print( "response empty: not japanese?\n", .{} );
    return;
  }

  const data = &parsed.value.data[0];

  // Good Enough:tm:
  var buf: [64000]u8 = undefined;
  const str = formatDef( &buf, data, definitions_count - 1, senses_count - 1 ) catch |e| {
    if( e == error.NotJapanese ) {
      z.debug.print( "response empty: not japanese?\n", .{} );
      return;
    }
    return e;
  };
  try z.io.getStdOut().writer().print( "{s}\n", .{str} );

  parsed.deinit();
  alloc.free( word );
  alloc.free( res );
  _ = gpa.deinit();
}
