// cdn_upload.js FILE_NAME BUCKET CDN_DISTRIBUTION_ID
// Will upload FILE_NAME to S3 BUCKET_NAME and then invalidate the same URL in the CDN

let file_name = process.argv[ 2 ]
let bucket = process.argv[ 3 ]
let s3_path = process.argv[ 4 ]
let cdn_distribution = process.argv[ 5 ]

// CREDENTIALS
// Credenetials are passed via environment variables. E.g.:
// export AWS_ACCESS_KEY_ID=xxx
//    # The access key for your AWS account.
// $ export AWS_SECRET_ACCESS_KEY=xxx
//    # The secret access key for your AWS account.
// $ export AWS_SESSION_TOKEN=xxx
//    # The session key for your AWS account. This is needed only when you are using temporary credentials.
//    # The AWS_SECURITY_TOKEN environment variable can also be used, but is only supported for backward compatibility purposes.
//    # AWS_SESSION_TOKEN is supported by multiple AWS SDKs

const fs = require( 'fs' );
const path = require( 'path' );
var AWS = require( 'aws-sdk' ); // Load the SDK for JavaScript

// AWS.config.update({region: 'us-east-1'}); // Set the Region -- doesn't matter for file copy
var s3 = new AWS.S3( { apiVersion: '2006-03-01' } ); // Create S3 service object
var cloudfront = new AWS.CloudFront( { apiVersion: '2019-03-26' } );

var upload_params = { Bucket: bucket, Key: '', Body: '' };

// Configure the file stream and obtain the upload parameters
var file_stream = fs.createReadStream( file_name );
file_stream.on( 'error', function ( err ) {
    console.error( 'File Error', err );
    process.exit( 1 )
} );

upload_params.Body = file_stream;
upload_params.Key = s3_path + '/' + path.basename( file_name );

// call S3 to retrieve upload file to specified bucket
s3.upload( upload_params, function ( err, data ) {
    if ( err ) {
        console.error( "Error", err );
    } if ( data ) {
        console.log( "Upload Success", data.Location );
    }
} );

// Invalidate Cache
var params = {
    DistributionId: cdn_distribution, // required
    InvalidationBatch: { //
        CallerReference: Date.now().toString(), /* required - if this is the same between runs AWS will ignore any second attempts to do the *same* invalidation */
        Paths: { /* required */
            Quantity: 1, // Required
            Items: [
                '/' + s3_path + '/' + path.basename( file_name ),
            ]
        }
    }
};


cloudfront.createInvalidation( params, function ( err, data ) {
    if ( err ) {
        console.log( err, err.stack ); // an error occurred
        process.exit( 1 );
    } else {
        console.log( `Invalidation Requested: ${ data.Location }` )
        console.log( `Invalidation State: ${ data.Invalidation.Status }` )
        console.log( `Invalidation Created Time: ${ data.Invalidation.CreateTime }` )
        console.log( `Invalidation Quantity: ${ data.Invalidation.InvalidationBatch.Paths.Quantity }` )
        console.log( `Invalidation Items: ${ data.Invalidation.InvalidationBatch.Paths.Items }` )
    }
} );
