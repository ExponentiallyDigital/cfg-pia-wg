// plain_error.dart - an exception's message as a user reads it.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// `Exception('x').toString()` is "Exception: x". The same tidy-up was written out 36 times across
// eleven files until build 508 (ID-041 step 1); one function keeps them all saying the same thing.

/// The text Dart prefixes to an [Exception]'s message.
const String kExceptionPrefix = 'Exception: ';

/// [error]'s message without the "Exception: " Dart puts in front of it, wherever it appears.
String plainError(Object error) => error.toString().replaceAll(kExceptionPrefix, '');
