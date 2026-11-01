# TukTak24 Storefront

A responsive Bengali-first storefront starter for TukTak24.

## Current status
- Responsive landing page, category filters, product search, cart and WhatsApp order link.
- Admin interface is a scaffold only. Authentication, persistent product database and image uploads are NOT enabled yet.
- Demo products (when admin flow is enabled locally) use browser localStorage and are not shared between customers/devices.

## Required production setup
Connect a Supabase project before enabling admin operations:
1. Create a Supabase project.
2. Create an Auth user for the store owner.
3. Create a `products` table and public `product-images` storage bucket.
4. Add row-level security policies so only the approved admin can insert/update/delete products and upload images.
5. Put the Supabase project URL and anon/public key in the frontend configuration. Never put a service-role key in browser code.
6. Verify all RLS policies before publishing.

## Contact
WhatsApp: 01938289730
Email: TukTak24@gmail.com
