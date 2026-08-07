create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;

alter default privileges in schema public
  revoke execute on functions from public;
