#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "libbel.h"
#include "bel-ast.h"
#include "bel-node-stack.h"

%%{
    machine set;
    write data;
}%%

bel_ast* bel_parse_term(char* line) {
    int             cs;
    char            *p;
    char            *pe;
    int             top;
    int             *stack;
    bel_ast_node*   term;
    bel_ast_node*   current_nv;
    bel_ast_node*   arg;
    bel_ast*        ast;
    bel_node_stack* term_stack;
    char            *function;
    char            *value;
    int             fi;
    int             vi;

    // Copy line to stack; Append new line if needed.
    int             line_length = strlen(line);
    int             i;
    char            input[line_length + 2];
    strcpy(input, line);
    for (i = line_length - 1; (input[i] == '\n' || input[i] == '\r'); i--)
        input[i] = '\0';
    input[i + 1] = '\n';
    input[i + 2] = '\0';

    p            = input;
    pe           = input + strlen(input);
    top          = 0;
    stack        = malloc(sizeof(int) * TERM_STACK_SIZE);
    current_nv   = NULL;
    function     = malloc(sizeof(char) * BEL_VALUE_CHAR_LEN);
    value        = malloc(sizeof(char) * BEL_VALUE_CHAR_LEN);
    fi           = 0;
    vi           = 0;

    term_stack   = stack_init(TERM_STACK_SIZE);
    term         = bel_new_ast_node_token(BEL_TOKEN_TERM);
    ast          = bel_new_ast();
    ast->root    = term;

    stack_push(term_stack, term);
    memset(function, '\0', BEL_VALUE_CHAR_LEN);
    memset(value, '\0', BEL_VALUE_CHAR_LEN);

    %%{
        action fxc {
            fi = 0;
            memset(function, '\0', BEL_VALUE_CHAR_LEN);
        }

        action valc {
            vi = 0;
            memset(value, '\0', BEL_VALUE_CHAR_LEN);
        }

        action fxn {
            function[fi++] = fc;
        }

        action valn {
            value[vi++] = fc;
        }

        action FX {
            term               = stack_peek(term_stack);
            term->token->left  = bel_new_ast_node_value(BEL_VALUE_FX, function);
            term->token->right = bel_new_ast_node_token(BEL_TOKEN_ARG);
        }

        action NESTED_FX {
            bel_ast_node* term_top = stack_peek(term_stack);

            // find ARG leaf
            arg = term_top->token->right;
            while(arg->token->right != NULL) {
                arg = arg->token->right;
            }

            // create new nested term
            term               = bel_new_ast_node_token(BEL_TOKEN_TERM);
            term->token->left  = bel_new_ast_node_value(BEL_VALUE_FX, function);
            term->token->right = bel_new_ast_node_token(BEL_TOKEN_ARG);
            // set head term, left: new nested term, right: next arg
            arg->token->left   = term;
            arg->token->right  = bel_new_ast_node_token(BEL_TOKEN_ARG);

            // push new nested term onto stack
            stack_push(term_stack, term);
        }

        action PFX {
            term = stack_peek(term_stack);

            // find ARG leaf
            arg = term->token->right;
            while(arg->token->right != NULL) {
                arg = arg->token->right;
            }

            current_nv               = bel_new_ast_node_token(BEL_TOKEN_NV);
            current_nv->token->left  = bel_new_ast_node_value(BEL_VALUE_PFX, value);
            current_nv->token->right = bel_new_ast_node_value(BEL_VALUE_VAL, NULL);
            arg->token->left         = current_nv;
            arg->token->right        = bel_new_ast_node_token(BEL_TOKEN_ARG);
        }

        action VAL {
            if (!current_nv) {
                term = stack_peek(term_stack);

                // find ARG leaf
                arg = term->token->right;
                while(arg->token->right != NULL) {
                    arg = arg->token->right;
                }

                current_nv               = bel_new_ast_node_token(BEL_TOKEN_NV);
                current_nv->token->left  = bel_new_ast_node_value(BEL_VALUE_PFX, NULL);
                current_nv->token->right = bel_new_ast_node_value(BEL_VALUE_VAL, value);
                arg->token->left         = current_nv;
                arg->token->right        = bel_new_ast_node_token(BEL_TOKEN_ARG);
            } else {
                current_nv->token->right = bel_new_ast_node_value(BEL_VALUE_VAL, value);
            }

            current_nv = 0;
        }

        action FCALL {
            fcall arguments;
        }

        action FRET {
            stack_pop(term_stack);
            fret;
        }

        SP           = ' ' | '\t';
        O_PAREN      = '(';
        C_PAREN      = ')';
        COLON        = ':';
        IDENT        = [a-zA-Z0-9_];
        IDENT_TOKEN  = IDENT+;
        STRING_TOKEN = '"' ('\\\"' | [^"])* '"';

        arguments :=
            (
                (IDENT_TOKEN >valc $valn ':')? @PFX (STRING_TOKEN|IDENT_TOKEN) >valc $valn %VAL |
                IDENT_TOKEN  >fxc $fxn %NESTED_FX O_PAREN @FCALL
            )
            (
                SP* ',' SP*
                (
                    (IDENT_TOKEN >valc $valn ':')? @PFX (STRING_TOKEN|IDENT_TOKEN) >valc $valn %VAL |
                    IDENT_TOKEN  >fxc $fxn %NESTED_FX O_PAREN @FCALL
                )
            )* C_PAREN @FRET;

        term :=
            IDENT_TOKEN >fxc $fxn %FX O_PAREN @FCALL C_PAREN;

        # Initialize and execute.
        write init;
        write exec;
    }%%

    // free allocations
    if (term_stack) {
        stack_destroy(term_stack);
    }
    free(stack);
    free(function);
    free(value);

    return ast;
};
// vim: ft=c sw=4 ts=4 sts=4 expandtab

