/*
 * SMJFilterCompiler.m
 *
 * Copyright 2017 Avérous Julien-Pierre
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


/* Adapted from https://github.com/json-path/JsonPath/blob/master/json-path/src/main/java/com/jayway/jsonpath/internal/filter/FilterCompiler.java */


#import "SMJFilterCompiler.h"

#import "SMJCharacterIndex.h"

#import "SMJLogicalOperator.h"
#import "SMJValueNode.h"

#import "SMJExpressionNode.h"
#import "SMJLogicalExpressionNode.h"
#import "SMJRelationalExpressionNode.h"


NS_ASSUME_NONNULL_BEGIN


/*
** Defines
*/
#pragma mark - Defines

#define kDocContextChar 		'$'
#define kEvalContextChar 		'@'

#define kOpenSquareBracketChar	'['
#define kCloseSquareBracketChar	']'
#define kOpenParenthesisChar 	'('
#define kCloseParenthesisChar 	')'
#define kOpenObjectChar 		'{'
#define kCloseObjectChar 		'}'
#define kOpenArrayChar 			'['
#define kCloseArrayChar 		']'

#define kSingleQuoteChar 		'\''
#define kDoubleQuoteChar 		'"'

#define kSpaceChar 				' '
#define kPeriodChar 			'.'

#define kAndChar				'&'
#define kOrChar 				'|'

#define kMinusChar 				'-'
#define kLessThanChar 			'<'
#define kGreaterThanChar 		'>'
#define kEqualChar 				'='
#define kTildeChar 				'~'
#define kTrueChar 				't'
#define kFalseChar 				'f'
#define kNullChar				'n'
#define kNotChar 				'!'
#define kPatternChar			'/'
#define kIgnoreCaseChar 		'i'


/*
** Macros
*/
#pragma mark - Macros

#define SMSetError(Error, Code, Message, ...) \
	do { \
		if ((Error) && *(Error) == nil) {\
			NSString *___message = [NSString stringWithFormat:(Message), ## __VA_ARGS__];\
			*(Error) = [NSError errorWithDomain:@"SMJFilterCompilerErrorDomain" code:(Code) userInfo:@{ NSLocalizedDescriptionKey : ___message }]; \
		} \
	} while (0) \



/*
** SMJCompiledFilter - Interface
*/
#pragma mark - SMJCompiledFilter - Interface

@interface SMJCompiledFilter : SMJFilter

- (instancetype)initWithPredicate:(id <SMJPredicate>)predicate;

@end



/*
** SMJFilterCompiler
*/
#pragma mark - SMJFilterCompiler

@implementation SMJFilterCompiler
{
	SMJCharacterIndex *_filter;
}


/*
** SMJFilterCompiler - Instance
*/
#pragma mark - SMJFilterCompiler - Instance

- (nullable instancetype)initWithFilterString:(NSString *)filterString error:(NSError **)error
{
	self = [super init];
	
	if (self)
	{
		_filter =  [[SMJCharacterIndex alloc] initWithString:filterString];
		
		[_filter trim];
		
		if (![_filter currentCharacterIsEqualTo:'['] || ![_filter lastCharacterIsEqualTo:']'])
		{
			SMSetError(error, 1, @"Filter must start with '[' and end with ']'. %@", filterString);
			return nil;
		}
		
		[_filter incrementPositionBy:1];
		[_filter decrementEndPositionBy:1];
		
		[_filter trim];
		
		if (![_filter currentCharacterIsEqualTo:'?'])
		{
			SMSetError(error, 2, @"Filter must start with '[?' and end with ']'. %@", filterString);
			return nil;
		}
		
		[_filter incrementPositionBy:1];
		
		[_filter trim];
		
		if (![_filter currentCharacterIsEqualTo:'('] || ![_filter lastCharacterIsEqualTo:')'])
		{
			SMSetError(error, 3, @"Filter must start with '[?(' and end with ')]'. %@", filterString);
			return nil;
		}
	}
	
	return self;
}


/*
** SMJFilterCompiler - Compile
*/
#pragma mark - SMJFilterCompiler - Compile

+ (nullable SMJFilter *)compileFilterString:(NSString *)filterString error:(NSError **)error
{
	SMJFilterCompiler *compiler = [[SMJFilterCompiler alloc] initWithFilterString:filterString error:error];
	
	if (!compiler)
		return nil;
	
	id <SMJPredicate> predicate = [compiler compileWithError:error];
	
	if (!predicate)
		return nil;
	
//	SMJRelationalExpressionNode *pr = predicate;
	
	return [[SMJCompiledFilter alloc] initWithPredicate:predicate];
}

- (nullable id <SMJPredicate>)compileWithError:(NSError **)error
{
	SMJExpressionNode *result = [self readLogicalORWithError:error];
	
	if (!result)
		return result;
	
	[_filter skipBlanks];
	
	if ([_filter inBounds])
	{
		SMSetError(error, 1, @"Expected end of filter expression instead of: %@", [_filter stringFromIndex:_filter.position toIndex:_filter.length]);
		return nil;
	}
	
	return result;
}


/*
 *  LogicalOR               = LogicalAND { '||' LogicalAND }
 *  LogicalAND              = LogicalANDOperand { '&&' LogicalANDOperand }
 *  LogicalANDOperand       = RelationalExpression | '(' LogicalOR ')' | '!' LogicalANDOperand
 *  RelationalExpression    = Value [ RelationalOperator Value ]
 */

- (nullable SMJExpressionNode *)readLogicalORWithError:(NSError **)error
{
	NSMutableArray <SMJExpressionNode *> *ops = [NSMutableArray array];
	
	SMJExpressionNode *logicalAND = [self readLogicalANDWithError:error];
	
	if (!logicalAND)
		return nil;
	
	[ops addObject:logicalAND];
	
	while (YES)
	{
		NSInteger	savepoint = _filter.position;
		NSError		*lerror = nil;
		
		if ([_filter readSignificantString:SMJLogicalOperatorOR error:&lerror] == NO)
		{
			[_filter setPosition:savepoint];
			break;
		}
		
		SMJExpressionNode *logicalAND = [self readLogicalANDWithError:&lerror];

		if (!logicalAND)
		{
			[_filter setPosition:savepoint];
			break;
		}
		
		[ops addObject:logicalAND];
	}
	
	return (ops.count == 1 ? [ops firstObject] : [SMJLogicalExpressionNode logicalOrWithExpressionNodes:ops]);
}
			
- (nullable SMJExpressionNode *)readLogicalANDWithError:(NSError **)error
{
	NSMutableArray <SMJExpressionNode *> *ops = [NSMutableArray array];

	SMJExpressionNode *logicalAND = [self readLogicalANDOperandWithError:error];

	if (!logicalAND)
		return nil;
	
	[ops addObject:logicalAND];
	
	while (YES)
	{
		NSInteger	savepoint = _filter.position;
		NSError		*lerror = nil;

		if ([_filter readSignificantString:SMJLogicalOperatorAND error:&lerror] == NO)
		{
			[_filter setPosition:savepoint];
			break;
		}
		
		SMJExpressionNode *logicalAND = [self readLogicalANDOperandWithError:&lerror];

		if (!logicalAND)
		{
			[_filter setPosition:savepoint];
			break;
		}
		
		[ops addObject:logicalAND];
	}
	
	return (ops.count == 1 ? [ops firstObject] : [SMJLogicalExpressionNode logicalAndWithExpressionNodes:ops]);
}

- (nullable SMJExpressionNode *)readLogicalANDOperandWithError:(NSError **)error
{
	NSInteger savepoint = [_filter skipBlanks].position;
	
	if ([[_filter skipBlanks] currentCharacterIsEqualTo:kNotChar])
	{
		if ([_filter readSignificantCharacter:kNotChar error:error] == NO)
			return nil;
		
		switch ([_filter skipBlanks].currentCharacter)
		{
			case kDocContextChar:
			case kEvalContextChar:
			{
				[_filter setPosition:savepoint];
				break;
			}
			default:
			{
				SMJExpressionNode *op = [self readLogicalANDOperandWithError:error];
				
				if (!op)
					return nil;
				
				return [SMJLogicalExpressionNode logicalNotWithExpressionNode:op];
			}
		}
	}
	
	if ([[_filter skipBlanks] currentCharacterIsEqualTo:kOpenParenthesisChar])
	{
		if ([_filter readSignificantCharacter:kOpenParenthesisChar error:error] == NO)
			return nil;
		
		SMJExpressionNode *op = [self readLogicalORWithError:error];
		
		if (!op)
			return nil;
		
		if ([_filter readSignificantCharacter:kCloseParenthesisChar error:error] == NO)
			return nil;
		
		return op;
	}
	
	return [self readExpressionWithError:error];
}


- (SMJRelationalExpressionNode *)readExpressionWithError:(NSError **)error
{
	SMJValueNode 			*left;
	SMJRelationalOperator	*operator;
	SMJValueNode			*right;
	
	//
	left = [self readValueNodeWithError:error];
	
	if (!left)
		return nil;
	
	NSInteger savepoint = _filter.position;
	
	//
	operator = [self readRelationalOperatorWithError:nil];
	
	if (operator)
	{
		SMJValueNode *right = [self readValueNodeWithError:nil];
		
		if (right)
			return [SMJRelationalExpressionNode relationExpressionNodeWithLeftValue:left operator:operator rightValue:right];
	}
	
	//
	[_filter setPosition:savepoint];
	
	if ([left isKindOfClass:[SMJPathNode class]] == NO)
	{
		SMSetError(error, 1, @"path node expected");
		return nil;
	}
	
	SMJPathNode *pathNode = (SMJPathNode *)left;
	
	left = [pathNode copyWithExistsCheckAndShouldExists:pathNode.shouldExists];
	right = pathNode.shouldExists ? [SMJValueNode valueNodeTRUE] : [SMJValueNode valueNodeFALSE];

	operator = [SMJRelationalOperator relationalOperatorEXISTS];
	
	return [SMJRelationalExpressionNode relationExpressionNodeWithLeftValue:left operator:operator rightValue:right];
}

- (nullable SMJLogicalOperator *)readLogicalOperatorWithError:(NSError **)error
{
	NSInteger begin = [_filter skipBlanks].position;
	NSInteger end = begin + 1;
	
	if (![_filter isInBoundsIndex:end])
	{
		SMSetError(error, 1, @"Expected boolean literal");
		return nil;
	}
	
	NSString *logicalOperator = [_filter stringFromIndex:begin toIndex:end + 1];
	
	if (![logicalOperator isEqualToString:@"||"] && ![logicalOperator isEqualToString:@"&&"])
	{
		SMSetError(error, 2, @"Expected logical operator");
		return nil;
	}
	
	[_filter incrementPositionBy:logicalOperator.length];

	//logger.trace("LogicalOperator from {} to {} -> [{}]", begin, end, logicalOperator);
	
	return [SMJLogicalOperator logicalOperatorFromString:logicalOperator error:error];
}

- (nullable SMJRelationalOperator *)readRelationalOperatorWithError:(NSError **)error
{
	NSInteger begin = [_filter skipBlanks].position;
	
	if ([self isRelationalOperatorChar:_filter.currentCharacter])
	{
		while ([_filter inBounds] && [self isRelationalOperatorChar:_filter.currentCharacter])
		{
			[_filter incrementPositionBy:1];
		}
	}
	else
	{
		while ([_filter inBounds] && _filter.currentCharacter != kSpaceChar)
		{
			[_filter incrementPositionBy:1];
		}
	}
	
	NSString *operator = [_filter stringFromIndex:begin toIndex:_filter.position];
		
	//logger.trace("Operator from {} to {} -> [{}]", begin, filter.position()-1, operator);
	
	return [SMJRelationalOperator relationalOperatorFromString:operator error:error];
}

- (nullable SMJValueNode *)readValueNodeWithError:(NSError **)error
{
	switch ([_filter skipBlanks].currentCharacter)
	{
		case kDocContextChar:
			return [self readPathWithError:error];
					
		case kEvalContextChar:
			return [self readPathWithError:error];
			
		case kNotChar:
		{
			[_filter incrementPositionBy:1];
			
			switch ([_filter skipBlanks].currentCharacter)
			{
				case kDocContextChar:
					return [self readPathWithError:error];
					
				case kEvalContextChar:
					return [self readPathWithError:error];
					
				default:
				{
					SMSetError(error, 1, @"Unexpected character '%c'", kNotChar);
					return nil;
				}
			}
		}
			
		default:
			return [self readLiteralWithError:error];
	}
}

- (nullable SMJValueNode *)readLiteralWithError:(NSError **)error
{
	switch ([_filter skipBlanks].currentCharacter)
	{
		case kSingleQuoteChar:
			return [self readStringLiteral:kSingleQuoteChar withError:error];
			
		case kDoubleQuoteChar:
			return [self readStringLiteral:kDoubleQuoteChar withError:error];
			
		case kTrueChar:
			return [self readBooleanLiteralWithError:error];
			
		case kFalseChar:
			return [self readBooleanLiteralWithError:error];
			
		case kMinusChar:
			return [self readNumberLiteralWithError:error];
			
		case kNullChar:
			return [self readNullLiteralWithError:error];
			
		case kOpenObjectChar:
			return [self readJsonLiteralWithError:error];
			
		case kOpenArrayChar:
			return [self readJsonLiteralWithError:error];
			
		case kPatternChar:
			return [self readPatternWithError:error];
			
		default:
			return [self readNumberLiteralWithError:error];
	}
}

- (nullable SMJNullNode *)readNullLiteralWithError:(NSError **)error
{
	//NSInteger begin = _filter.position;
	
	if (_filter.currentCharacter == kNullChar && [_filter isInBoundsIndex:_filter.position + 3])
	{
		NSString *nullValue = [_filter stringFromIndex:_filter.position toIndex:_filter.position + 4];
		
		if ([nullValue isEqualToString:@"null"])
		{
			//logger.trace("NullLiteral from {} to {} -> [{}]", begin, filter.position()+3, nullValue);
			
			[_filter incrementPositionBy:nullValue.length];
			
			return [SMJValueNode nullNode];
		}
	}
	
	SMSetError(error, 1, @"Expected <null> value");
	return nil;
}

- (nullable SMJJsonNode *)readJsonLiteralWithError:(NSError **)error
{
	NSInteger begin = _filter.position;
	
	unichar openChar = _filter.currentCharacter;
	
	if (openChar != kOpenArrayChar && openChar != kOpenObjectChar)
	{
		SMSetError(error, 1, @"internal error");
		return nil;
	}
	
	unichar closeChar = openChar == kOpenArrayChar ? kCloseArrayChar : kCloseObjectChar;
	
	NSInteger closingIndex = [_filter indexOfMatchingCloseCharacterFromIndex:_filter.position openCharacter:openChar closeCharacter:closeChar skipStrings:YES skipRegex:NO error:error];
							  
	
	if (closingIndex == NSNotFound)
	{
		SMSetError(error, 2, @"String not closed. Expected %c in %@", kSingleQuoteChar, _filter);
		return nil;
	}
	else
	{
		[_filter setPosition:closingIndex + 1];
	}
	
	NSString *json = [_filter stringFromIndex:begin toIndex:_filter.position];
	
	//logger.trace("JsonLiteral from {} to {} -> [{}]", begin, filter.position(), json);
	
	return [SMJValueNode jsonNodeWithString:json];
}

- (nullable SMJPatternNode *)readPatternWithError:(NSError **)error
{
	NSInteger begin = _filter.position;
	NSInteger closingIndex = [_filter nextIndexOfUnescapedCharacter:kPatternChar];
	
	if (closingIndex == NSNotFound)
	{
		SMSetError(error, 1, @"Pattern not closed. Expected %c in %@", kPatternChar, _filter);
		return nil;
	}
	else
	{
		if ([_filter isInBoundsIndex:closingIndex + 1] && ([_filter characterAtIndex:closingIndex + 1] == kIgnoreCaseChar))
		{
			closingIndex++;
		}
		
		[_filter setPosition:closingIndex + 1];
	}
	
	NSString *pattern = [_filter stringFromIndex:begin toIndex:_filter.position];
	
	//logger.trace("PatternNode from {} to {} -> [{}]", begin, filter.position(), pattern);
	
	return [SMJValueNode patternNodeWithString:pattern];
}

- (nullable SMJStringNode *)readStringLiteral:(unichar)endChar withError:(NSError **)error
{
	NSInteger begin = _filter.position;
	
	NSInteger closingSingleQuoteIndex = [_filter nextIndexOfUnescapedCharacter:endChar];
	
	if (closingSingleQuoteIndex == NSNotFound)
	{
		SMSetError(error, 1, @"String literal does not have matching quotes. Expected %c in %@", endChar, _filter);
		return nil;
	}
	else
	{
		[_filter setPosition:closingSingleQuoteIndex + 1];
	}
	
	NSString *stringLiteral = [_filter stringFromIndex:begin toIndex:_filter.position];
	
	//logger.trace("StringLiteral from {} to {} -> [{}]", begin, filter.position(), stringLiteral);
	
	return [SMJValueNode stringNodeWithString:stringLiteral escape:YES];
}


- (nullable SMJNumberNode *)readNumberLiteralWithError:(NSError **)error
{
	NSInteger begin = _filter.position;
	
	while ([_filter inBounds] && [_filter isNumberCharacterAtIndex:_filter.position])
	{
		[_filter incrementPositionBy:1];
	}
	
	NSString *numberLiteral = [_filter stringFromIndex:begin toIndex:_filter.position];
	
	//logger.trace("NumberLiteral from {} to {} -> [{}]", begin, filter.position(), numberLiteral);
	
	return [SMJValueNode numberNodeWithString:numberLiteral];
}

- (nullable SMJBooleanNode *)readBooleanLiteralWithError:(NSError **)error
{
	NSInteger begin = _filter.position;
	NSInteger end = _filter.currentCharacter == kTrueChar ? _filter.position + 3 : _filter.position + 4;
	
	if (![_filter isInBoundsIndex:end])
	{
		SMSetError(error, 1, @"Expected boolean literal");
		return nil;
	}
	
	NSString *boolValue = [_filter stringFromIndex:begin toIndex:end + 1];
	
	if (![boolValue isEqualToString:@"true"] && ![boolValue isEqualToString:@"false"])
	{
		SMSetError(error, 2, @"Expected boolean literal");
		return nil;
	}
	
	[_filter incrementPositionBy:boolValue.length];
	
	//logger.trace("BooleanLiteral from {} to {} -> [{}]", begin, end, boolValue);
	
	return [SMJValueNode booleanNodeWithString:boolValue];
}


- (nullable SMJPathNode *)readPathWithError:(NSError **)error
{
	unichar		previousSignificantChar = [_filter previousSignificantCharacter];
	NSInteger	begin = _filter.position;
	
	[_filter incrementPositionBy:1]; //skip $ and @
	
	while ([_filter inBounds])
	{
		if (_filter.currentCharacter == kOpenSquareBracketChar)
		{
			NSInteger closingSquareBracketIndex = [_filter indexOfMatchingCloseCharacterFromIndex:_filter.position openCharacter:kOpenSquareBracketChar closeCharacter:kCloseSquareBracketChar skipStrings:YES skipRegex:NO error:error];
			
			if (closingSquareBracketIndex == NSNotFound)
			{
				SMSetError(error, 1, @"Square brackets does not match in filter %@", _filter);
				return nil;
			}
			else
			{
				[_filter setPosition:closingSquareBracketIndex + 1];
			}
		}
		
		BOOL closingFunctionBracket = ((_filter.currentCharacter == kCloseParenthesisChar) && [self currentCharIsClosingFunctionBracket:begin]);
		BOOL closingLogicalBracket  = ((_filter.currentCharacter == kCloseParenthesisChar) && !closingFunctionBracket);
		
		if (![_filter inBounds] || [self isRelationalOperatorChar:_filter.currentCharacter] || (_filter.currentCharacter == kSpaceChar) || closingLogicalBracket)
		{
			break;
		}
		else
		{
			[_filter incrementPositionBy:1];
		}
	}
	
	BOOL		shouldExists = !(previousSignificantChar == kNotChar);
	NSString	*path = [_filter stringFromIndex:begin toIndex:_filter.position];
	
	return [SMJValueNode pathNodeWithPathString:path existsCheck:NO shouldExists:shouldExists error:error];
}


- (BOOL)expressionIsTerminated
{
	unichar c = _filter.currentCharacter;
	
	if ((c == kCloseParenthesisChar) || [self isLogicalOperatorChar:c])
	{
		return YES;
	}
	
	c = [_filter nextSignificantCharacter];
	
	if ((c == kCloseParenthesisChar) || [self isLogicalOperatorChar:c])
	{
		return YES;
	}
	
	return NO;
}

- (BOOL)currentCharIsClosingFunctionBracket:(NSInteger)lowerBound
{
	if (_filter.currentCharacter != kCloseParenthesisChar)
	{
		return NO;
	}
	
	NSInteger idx = [_filter indexOfPreviousSignificantCharacter];
	
	if ((idx == NSNotFound) || ([_filter characterAtIndex:idx] != kOpenParenthesisChar))
	{
		return NO;
	}
	
	idx--;
	
	while ([_filter isInBoundsIndex:idx] && idx > lowerBound)
	{
		if ([_filter characterAtIndex:idx] == kPeriodChar)
		{
			return YES;
		}
		
		idx--;
	}
	
	return NO;
}

- (BOOL)isLogicalOperatorChar:(unichar)c
{
	return c == kAndChar || c == kOrChar;
}

- (BOOL)isRelationalOperatorChar:(unichar)c
{
	return c == kLessThanChar || c == kGreaterThanChar || c == kEqualChar || c == kTildeChar || c == kNotChar;
}

@end



/*
** SMJCompiledFilter
*/
#pragma mark - SMJCompiledFilter

@implementation SMJCompiledFilter
{
	id <SMJPredicate> _predicate;
}

/*
** SMJCompiledFilter - Instance
*/
#pragma mark - SMJCompiledFilter - Instance

- (instancetype)initWithPredicate:(id <SMJPredicate>)predicate
{
	self = [super init];
	
	if (self)
	{
		_predicate = predicate;
	}
	
	return self;
}


/*
** SMJCompiledFilter - SMFiler
*/
#pragma mark - SMJCompiledFilter - SMFiler

- (SMJPredicateApply)applyWithContext:(id <SMJPredicateContext>)context error:(NSError **)error
{
	return [_predicate applyWithContext:context error:error];
}

- (NSString *)stringValue
{
	NSString *predicateString = [_predicate stringValue];
	
	if ([predicateString hasPrefix:@"("])
		return [NSString stringWithFormat:@"[?%@]", predicateString];
	else
		return [NSString stringWithFormat:@"[?(%@)]", predicateString];
}

@end


NS_ASSUME_NONNULL_END

