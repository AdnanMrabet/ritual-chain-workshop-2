# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Ritual builders and prediction-market participants who want to take a position without exposing the crowd's direction during the entry window.

## Product Purpose

CipherBook demonstrates a complete self-resolving prediction market where each side is hidden until a dedicated reveal phase. Success means the contract compiles locally, its lifecycle is verifiable in tests, and the mechanism is understandable without a live deployment.

## Positioning

Unlike an open betting pool, CipherBook commits only a hash and stake first. The side and salt are revealed later, reducing copycat behavior and late momentum chasing.

## Capabilities and Constraints

The Solidity contract uses Ritual Scheduler, RitualWallet, the HTTP precompile, jq extraction, three bounded retries, pull payments, refundable invalid markets, and permissionless expiry. No deployed contract or hosted site is claimed. Demonstration data in the interface is explicitly illustrative.

## Evidence on Hand

The repository contains the contract, eight local Solidity tests, build scripts, and a static interactive walkthrough. No wallet key, contract address, transaction hash, customer proof, or production telemetry is available.

## Product Principles

- Keep a position private until reveal.
- Make every lifecycle boundary explicit.
- Never turn oracle failure into a NO outcome.
- Keep recovery permissionless and funds pull-based.

